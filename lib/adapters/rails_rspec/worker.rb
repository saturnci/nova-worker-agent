# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'json'
require_relative '../../saturn_ci_worker_api/request'
require_relative '../../saturn_ci_worker_api/stream'
require_relative '../../saturn_ci_worker_api/file_content_request'
require_relative '../../executor/docker_compose_configuration'

module Adapters
  module RailsRSpec
    class Worker
      DOCKER_SERVICE_NAME = 'saturn_test_app'
      DOCKER_COMPOSE_FILE = '.saturnci/docker-compose.yml'

      def self.docker_compose_project_name
        task_id = ENV.fetch('TASK_ID')
        raise 'TASK_ID is empty' if task_id.to_s.strip.empty?

        "task-#{task_id}"
      end

      def self.docker_compose_base_command
        project_name = docker_compose_project_name
        raise 'docker_compose_project_name is empty' if project_name.to_s.strip.empty?

        "docker-compose -p #{project_name} -f #{DOCKER_COMPOSE_FILE}"
      end

      def initialize(executor)
        @executor = executor
      end

      protected

      def execute_test_workflow
        run_tests
        finish
      rescue StandardError => e
        puts "ERROR: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n")
      ensure
        @executor.finish
        @executor.clean_up_docker
        @executor.kill_stream
      end

      private

      def finish
        send_results
        puts 'Task finished.'
        @executor.finish
      end

      def task_info
        @executor.task_info
      end

      def test_suite_run_id
        task_info['test_suite_run_id']
      end

      def clone_and_configure
        @executor.clone_repo
        @executor.send_task_event('repo_cloned')
        @executor.write_env_file

        puts 'Copying database.yml...'
        FileUtils.cp('.saturnci/database.yml', 'config/database.yml')

        sanitize_docker_compose
      end

      def sanitize_docker_compose
        puts 'Sanitizing docker-compose.yml (removing port bindings)...'
        docker_compose_path = DOCKER_COMPOSE_FILE
        original_content = File.read(docker_compose_path)
        config = Executor::DockerComposeConfiguration.new(original_content)
        File.write(docker_compose_path, config.sanitized_content)
      end

      def prepare_docker
        @executor.wait_for_docker_daemon
        @executor.preload_vendor_images

        puts 'Preloading app image...'
        @executor.preload_app_image

        ENV['SATURN_TEST_APP_IMAGE_URL'] = 'saturnci-local'
      end

      def setup_database
        puts 'Setting up database...'
        system("#{self.class.docker_compose_base_command} run #{DOCKER_SERVICE_NAME} bundle exec rails db:create db:schema:load 2>&1")
        @executor.send_task_event('database_setup_finished')
      end

      def run_dry_run
        puts 'Running dry run to get test case identifiers...'
        command = "#{self.class.docker_compose_base_command} run #{DOCKER_SERVICE_NAME} bundle exec rspec --dry-run --format json ./spec"
        puts 'Command:'
        puts command
        dry_run_json = `#{command}`
        @test_case_identifiers = JSON.parse(dry_run_json)['examples'].map { |example| example['id'] }
        puts "Found #{@test_case_identifiers.count} test cases"
        @executor.send_task_event('dry_run_finished')
      end

      def run_tests
        puts 'Running tests...'
        setup_test_output_stream

        execute_tests

        sleep 2
        @test_output_stream.kill

        puts "COMMAND_EXIT_CODE=\"#{@rspec_exit_code}\""
      end

      def setup_test_output_stream
        test_output_file = "#{Executor.project_dir}/tmp/test_output.txt"
        FileUtils.mkdir_p(File.dirname(test_output_file))
        File.write(test_output_file, '')

        @test_output_stream = SaturnCIWorkerAPI::Stream.new(
          test_output_file,
          "tasks/#{ENV.fetch('TASK_ID')}/test_output",
          wait_interval: 1
        )
        @test_output_stream.start
      end

      def fetch_test_set
        puts 'Getting test case instructions from server...'
        test_set_response = SaturnCIWorkerAPI::Request.new(
          host: ENV.fetch('SATURNCI_API_HOST'),
          method: :post,
          endpoint: "test_suite_runs/#{test_suite_run_id}/test_set",
          body: { test_files: @test_case_identifiers }.to_json
        ).execute

        test_set_data = JSON.parse(test_set_response.body)
        @grouped_tests = test_set_data['grouped_tests']
        @dry_run_example_count = test_set_data['dry_run_example_count']
        @executor.send_task_event('test_set_received')

        raise 'dry_run_example_count not set by server' if @dry_run_example_count.nil?

        puts "dry_run_example_count: #{@dry_run_example_count}"
      end

      def execute_tests
        rspec_command = [
          'bundle exec rspec',
          '--format documentation',
          '--format documentation --out tmp/test_output.txt',
          '--format json --out tmp/json_output.json',
          '--force-color',
          "--order rand:#{task_info['rspec_seed']}",
          @grouped_tests[task_info['run_order_index'].to_s].join(' ')
        ].join(' ')

        docker_command = "#{self.class.docker_compose_base_command} run #{DOCKER_SERVICE_NAME} #{rspec_command}"
        puts "Running command: #{docker_command}"
        @executor.send_task_event('tests_started')
        system("#{docker_command} 2>&1")
        @rspec_exit_code = $CHILD_STATUS.exitstatus
        @executor.send_task_event('tests_finished')
      end

      def precompile_assets
        puts 'Precompiling assets...'
        system("#{self.class.docker_compose_base_command} run #{DOCKER_SERVICE_NAME} bundle exec rails assets:precompile 2>&1")
        @executor.send_task_event('assets_precompiled')
      end

      def send_results
        puts 'Sending JSON output...'
        json_output_request = SaturnCIWorkerAPI::FileContentRequest.new(
          host: ENV.fetch('SATURNCI_API_HOST'),
          api_path: "tasks/#{ENV.fetch('TASK_ID')}/json_output",
          content_type: 'application/json',
          file_path: "#{Executor.project_dir}/tmp/json_output.json"
        )
        response = json_output_request.execute
        puts "JSON output response code: #{response.code}"
        puts response.body
      end
    end
  end
end
