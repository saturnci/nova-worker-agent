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

  describe '#sanitized_content' do
    it 'removes ports from all services' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          postgres:
            image: postgres:17.2-alpine
            ports:
              - "127.0.0.1:5432:5432"
          redis:
            image: redis:4.0.14-alpine
            ports:
              - "6379:6379"
          app:
            image: myapp:latest
      YAML

      config = described_class.new(yaml_content)
      sanitized = YAML.safe_load(config.sanitized_content)

      expect(sanitized['services']['postgres']).not_to have_key('ports')
      expect(sanitized['services']['redis']).not_to have_key('ports')
      expect(sanitized['services']['app']['image']).to eq('myapp:latest')
    end

    it 'preserves other service configuration' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          postgres:
            image: postgres:17.2-alpine
            ports:
              - "5432:5432"
            environment:
              POSTGRES_USER: test
            volumes:
              - pgdata:/var/lib/postgresql/data
        volumes:
          pgdata:
      YAML

      config = described_class.new(yaml_content)
      sanitized = YAML.safe_load(config.sanitized_content)

      expect(sanitized['services']['postgres']).not_to have_key('ports')
      expect(sanitized['services']['postgres']['environment']).to eq({ 'POSTGRES_USER' => 'test' })
      expect(sanitized['services']['postgres']['volumes']).to eq(['pgdata:/var/lib/postgresql/data'])
      expect(sanitized['volumes']).to eq({ 'pgdata' => nil })
    end

    it 'handles services without ports' do
      yaml_content = <<~YAML
        version: "3.8"
        services:
          app:
            image: myapp:latest
            environment:
              RAILS_ENV: test
      YAML

      config = described_class.new(yaml_content)
      sanitized = YAML.safe_load(config.sanitized_content)

      expect(sanitized['services']['app']['image']).to eq('myapp:latest')
      expect(sanitized['services']['app']['environment']).to eq({ 'RAILS_ENV' => 'test' })
    end
  end
end
