# frozen_string_literal: true

require 'English'
class DryRun
  def initialize(docker_service_name:, image_url:)
    @docker_service_name = docker_service_name
    @image_url = image_url
  end

  def command
    "SATURN_TEST_APP_IMAGE_URL=#{@image_url} \\\n" \
      "docker-compose -f .saturnci/docker-compose.yml \\\n" \
      "run -T #{@docker_service_name} \\\n" \
      'bundle exec rspec --dry-run'
  end

  def expected_count
    puts 'Full dry run output:'
    puts full_output
    puts "Dry run exit code: #{@exit_code}"

    raise "RSpec dry-run failed with exit code #{@exit_code}" if @exit_code != 0

    line_with_count = full_output.split("\n").find { |line| line.match(/(\d+) example/) }

    raise 'Could not find example count in RSpec dry-run output' if line_with_count.nil?

    line_with_count.match(/(\d+) example/)[1].to_i
  end

  def full_output
    @full_output ||= command_output.tap { @exit_code = last_exit_code }
  end

  def command_output
    `#{command} 2>&1`
  end

  def last_exit_code
    $CHILD_STATUS.exitstatus
  end
end
