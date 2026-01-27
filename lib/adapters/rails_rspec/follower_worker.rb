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
