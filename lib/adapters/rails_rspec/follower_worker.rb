# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class FollowerWorker < Worker
      def run
        puts 'Adapter: Ruby on Rails/RSpec (Follower)'
        @executor.send_worker_event('worker_started')

        clone_and_configure
        prepare_docker
        setup_database
        precompile_assets

        execute_test_workflow
      end
    end
  end
end
