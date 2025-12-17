# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class FollowerWorker < Worker
      def run
        puts 'Adapter: Ruby on Rails/RSpec (Follower)'
        @executor.send_worker_event('worker_started')

        clone_and_configure
        @executor.wait_for_setup_complete
        prepare_docker
        precompile_assets
        fetch_test_set
        execute_test_workflow
      end
    end
  end
end
