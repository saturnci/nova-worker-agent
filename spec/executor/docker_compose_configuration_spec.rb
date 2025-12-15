# frozen_string_literal: true

require_relative '../../lib/executor/docker_compose_configuration'

RSpec.describe Executor::DockerComposeConfiguration do
  describe '#vendor_images' do
    it 'returns image names from services' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          postgres:
            image: postgres:17.2-alpine
          redis:
            image: redis:4.0.14-alpine
      YAML

      config = described_class.new(yaml_content)
      expect(config.vendor_images).to contain_exactly(
        'postgres:17.2-alpine',
        'redis:4.0.14-alpine'
      )
    end

    it 'excludes services that use build instead of image' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          saturn_test_app:
            build:
              context: ..
              dockerfile: .saturnci/Dockerfile
          postgres:
            image: postgres:17.2-alpine
      YAML

      config = described_class.new(yaml_content)
      expect(config.vendor_images).to eq(['postgres:17.2-alpine'])
    end

    it 'excludes services with image containing variable interpolation' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          saturn_test_app:
            image: ${SATURN_TEST_APP_IMAGE_URL:-saturnci-local}
          postgres:
            image: postgres:17.2-alpine
      YAML

      config = described_class.new(yaml_content)
      expect(config.vendor_images).to eq(['postgres:17.2-alpine'])
    end

    it 'returns empty array when no services have images' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          app:
            build: .
      YAML

      config = described_class.new(yaml_content)
      expect(config.vendor_images).to eq([])
    end
  end
end
