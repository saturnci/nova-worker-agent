# frozen_string_literal: true

require 'yaml'

class Executor
  class DockerComposeConfiguration
    def initialize(yaml_content)
      @config = YAML.safe_load(yaml_content)
    end

    def vendor_images
      services = @config['services'] || {}
      services.values.filter_map do |service|
        image = service['image']
        next if image.nil?
        next if image.include?('$')

        image
      end
    end
  end
end
