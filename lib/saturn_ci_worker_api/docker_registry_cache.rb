# frozen_string_literal: true

require 'English'
require 'digest'

module SaturnCIWorkerAPI
  class DockerRegistryCache
    URL = 'docker-image-registry.saturnci.com:5000'

    def initialize(username:, password:, project_name:, branch_name:)
      @username = username
      @password = password
      @project_name = project_name
      @branch_name = branch_name&.gsub(/[^a-zA-Z0-9_.-]/, '-')&.slice(0, 63)
    end

    def image_url
      "#{URL}/#{@project_name}"
    end

    def authenticate
      return false if @username.nil? || @password.nil?

      system("echo '#{@password}' | docker login #{URL} -u #{@username} --password-stdin")
      $CHILD_STATUS.success?
    end

    def pull_image
      output = `docker pull #{image_url} 2>&1`

      if output.include?('not found') || output.include?('manifest unknown')
        "Docker registry cache miss. Image not found in registry: #{image_url}"
      else
        'Docker registry cache hit'
      end
    end

    def push_image
      system("docker push #{image_url}")
    end
  end
end
