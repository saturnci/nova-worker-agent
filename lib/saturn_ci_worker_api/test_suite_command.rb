# frozen_string_literal: true

module SaturnCIWorkerAPI
  class TestSuiteCommand
    TEST_FILE_GLOB = './spec/**/*_spec.rb'

    def initialize(docker_service_name:, docker_registry_cache_image_url:, number_of_concurrent_runs:,
                   run_order_index:, rspec_seed:, rspec_documentation_output_filename:)
      @docker_service_name = docker_service_name
      @docker_registry_cache_image_url = docker_registry_cache_image_url
      @number_of_concurrent_runs = number_of_concurrent_runs.to_i
      @run_order_index = run_order_index.to_i
      @rspec_seed = rspec_seed.to_i
      @rspec_documentation_output_filename = rspec_documentation_output_filename
    end

    def docker_compose_command
      "docker-compose -f .saturnci/docker-compose.yml run #{@docker_service_name} #{rspec_command}"
    end

    def test_filenames_string(test_filenames)
      raise StandardError, "No test files found matching #{TEST_FILE_GLOB}" if test_filenames.empty?

      base_size = test_filenames.size / @number_of_concurrent_runs
      remainder = test_filenames.size % @number_of_concurrent_runs

      chunks = []
      start_index = 0

      @number_of_concurrent_runs.times do |i|
        chunk_size = base_size + (i < remainder ? 1 : 0)
        chunks << test_filenames[start_index, chunk_size]
        start_index += chunk_size
      end

      selected_test_filenames = chunks[@run_order_index - 1]
      selected_test_filenames.join(' ')
    end

    private

    def rspec_command
      [
        'bundle exec rspec',
        '--require ./.saturnci/rspec_retry.rb',
        '--format documentation',
        "--format documentation --out #{@rspec_documentation_output_filename}",
        '--format json --out tmp/json_output.json',
        '--force-color',
        "--order rand:#{@rspec_seed}",
        test_filenames_string(test_filenames)
      ].join(' ')
    end

    def test_filenames
      Dir.glob(TEST_FILE_GLOB).shuffle(random: Random.new(@rspec_seed))
    end
  end
end
