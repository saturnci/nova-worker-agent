# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class FollowerWorker < Worker
      private

      def setup
        puts "Follower worker (order_index: #{task_info['run_order_index']}): waiting for setup"

        @executor.wait_for_setup_complete
        clone_and_configure
        prepare_docker
        setup_database
        precompile_assets
      end
    end
  end
end
