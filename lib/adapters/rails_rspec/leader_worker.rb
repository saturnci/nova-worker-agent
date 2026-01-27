# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class LeaderWorker < Worker
      def run
        puts 'Adapter: Ruby on Rails/RSpec (Leader)'
        @executor.send_task_event('worker_started')

        clone_and_configure
        upload_docker_config
        prepare_docker
        setup_database
        precompile_assets
        run_dry_run
        fetch_test_set
        @executor.send_task_event('setup_completed')

        execute_test_workflow
      rescue StandardError => e
        puts "FATAL ERROR in LeaderWorker#run: #{e.class}: #{e.message}"
        puts e.backtrace.first(20).join("\n")
        $stdout.flush
      ensure
        @executor.finish
        @executor.clean_up_docker
        @executor.kill_stream
        FileUtils.rm_rf(Executor.project_dir)
      end

      private

      def upload_docker_config
        SaturnCIWorkerAPI::Request.new(
          host: ENV.fetch('SATURNCI_API_HOST'),
          method: :patch,
          endpoint: "test_suite_runs/#{test_suite_run_id}",
          body: {
            dockerfile_content: File.read('.saturnci/Dockerfile'),
            docker_compose_file_content: File.read('.saturnci/docker-compose.yml')
          }.to_json
        ).execute
      end
    end
  end
end
