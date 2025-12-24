# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class FollowerWorker < Worker
      SETUP_WAIT_INTERVAL = 3

      def run
        puts 'Adapter: Ruby on Rails/RSpec (Follower)'
        @executor.send_worker_event('worker_started')

        clone_and_configure
        prepare_docker
        setup_database
        precompile_assets

        wait_for_setup_complete
        fetch_test_set
        execute_test_workflow
      end

      def task_setup_completed?
        response = @executor.client.get("tasks/#{@executor.task_id}")
        JSON.parse(response.body)['setup_completed']
      end

      private

      def wait_for_setup_complete
        puts 'Waiting for setup to complete...'

        loop do
          if task_setup_completed?
            puts 'Setup complete, proceeding...'
            return
          end

          puts 'Setup not complete yet, polling...'
          sleep SETUP_WAIT_INTERVAL
        end
      end
    end
  end
end
