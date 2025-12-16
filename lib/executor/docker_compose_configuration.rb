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

    def sanitized_content
      sanitized_config = deep_dup(@config)
      services = sanitized_config['services'] || {}
      services.each_value do |service|
        service.delete('ports')
      end
      YAML.dump(sanitized_config)
    end

    private

    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        obj
      end
    end
  end
end
