# frozen_string_literal: true

require 'English'
require 'digest'

module SaturnCIWorkerAPI
  class DockerRegistryCache
    URL = 'docker-image-registry-service:5000'

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
  end
end
