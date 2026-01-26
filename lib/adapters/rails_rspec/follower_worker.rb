# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class FollowerWorker < Worker
      def run
        puts 'Adapter: Ruby on Rails/RSpec (Follower)'
        @executor.send_task_event('worker_started')

        clone_and_configure
        prepare_docker
        setup_database
        precompile_assets

        wait_for_setup_complete
        fetch_test_set
        execute_test_workflow
      rescue StandardError => e
        puts "FATAL ERROR in FollowerWorker#run: #{e.class}: #{e.message}"
        puts e.backtrace.first(20).join("\n")
        $stdout.flush
      ensure
        @executor.finish
        @executor.clean_up_docker
        @executor.kill_stream
        FileUtils.rm_rf(Executor.project_dir)
      end

      private

      def wait_for_setup_complete
        puts 'Waiting for setup to complete...'
        loop do
          if setup_completed?
            puts 'Setup complete, proceeding...'
            return
          end

          puts 'Setup not complete yet, polling...'
          sleep 2
        end
      end

      def setup_completed?
        response = @executor.client.get("tasks/#{@executor.task_id}")
        task_data = JSON.parse(response.body)
        task_data['setup_completed']
      end
    end
  end
end
