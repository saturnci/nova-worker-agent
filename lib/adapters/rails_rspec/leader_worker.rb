# frozen_string_literal: true

require_relative 'worker'

module Adapters
  module RailsRSpec
    class LeaderWorker < Worker
      private

      def setup
        puts 'Leader worker: performing full setup'

        clone_and_configure
        upload_docker_config
        prepare_docker
        @executor.send_worker_event('setup_completed')
        setup_database
        precompile_assets
      end

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
