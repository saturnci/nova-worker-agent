# frozen_string_literal: true

require_relative '../lib/cached_docker_image'

RSpec.describe Executor::CachedDockerImage do
  let(:image_name) { 'my-image:latest' }
  let(:cache_path) { '/shared/repo-123/image.tar' }
  let(:cache_key) { 'abc123def456' }
  let(:cache_key_path) { '/shared/repo-123/cache_key.txt' }
  let(:cached_image) { described_class.new(image_name: image_name, cache_path: cache_path, cache_key: cache_key) }

  describe '#load' do
    context 'when cache key file does not exist' do
      before do
        allow(File).to receive(:exist?).with(cache_key_path).and_return(false)
        allow(cached_image).to receive(:puts)
      end

      it 'returns false' do
        expect(cached_image.load).to be false
      end
    end

    context 'when cache key does not match' do
      before do
        allow(File).to receive(:exist?).with(cache_key_path).and_return(true)
        allow(File).to receive(:read).with(cache_key_path).and_return('different_key')
        allow(cached_image).to receive(:puts)
      end

      it 'returns false' do
        expect(cached_image.load).to be false
      end
    end

    context 'when cache key matches' do
      before do
        allow(File).to receive(:exist?).with(cache_key_path).and_return(true)
        allow(File).to receive(:read).with(cache_key_path).and_return(cache_key)
      end

      context 'when image already exists in Docker' do
        before do
          allow(cached_image).to receive(:system)
            .with("docker image inspect #{image_name} > /dev/null 2>&1")
            .and_return(true)
          allow(cached_image).to receive(:puts)
        end

        it 'returns true' do
          expect(cached_image.load).to be true
        end

        it 'does not run docker load' do
          expect(cached_image).not_to receive(:system).with("docker load < #{cache_path}")
          cached_image.load
        end
      end
    end

    context 'when cache key matches and image does not exist in Docker' do
      before do
        allow(File).to receive(:exist?).with(cache_key_path).and_return(true)
        allow(File).to receive(:read).with(cache_key_path).and_return(cache_key)
        allow(cached_image).to receive(:system)
          .with("docker image inspect #{image_name} > /dev/null 2>&1")
          .and_return(false)
        allow(cached_image).to receive(:puts)
      end

      context 'when cache file exists' do
        before do
          allow(File).to receive(:exist?).with(cache_path).and_return(true)
          allow(File).to receive(:size).with(cache_path).and_return(500_000_000)
        end

        context 'when docker load succeeds' do
          before do
            allow(cached_image).to receive(:run_docker_load).and_return(['Loaded image: my-image:latest', true, 1.5])
          end

          it 'returns true' do
            expect(cached_image.load).to be true
          end

          it 'runs docker load' do
            expect(cached_image).to receive(:run_docker_load)
            cached_image.load
          end
        end

        context 'when docker load fails' do
          before do
            allow(cached_image).to receive(:run_docker_load).and_return(['error: something went wrong', false, 0.5])
          end

          it 'returns false' do
            expect(cached_image.load).to be false
          end
        end
      end

      context 'when cache file does not exist' do
        before do
          allow(File).to receive(:exist?).with(cache_path).and_return(false)
        end

        it 'returns false' do
          expect(cached_image.load).to be false
        end
      end
    end
  end

  describe '#save' do
    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(cached_image).to receive(:system).and_return(true)
      allow(cached_image).to receive(:puts)
      allow(File).to receive(:exist?).with(cache_path).and_return(true)
      allow(File).to receive(:size).with(cache_path).and_return(500_000_000)
      allow(File).to receive(:write)
    end

    it 'creates the cache directory' do
      expect(FileUtils).to receive(:mkdir_p).with('/shared/repo-123')
      cached_image.save
    end

    it 'runs docker save' do
      expect(cached_image).to receive(:system).with("docker save #{image_name} > #{cache_path}")
      cached_image.save
    end

    it 'writes the cache key file' do
      expect(File).to receive(:write).with(cache_key_path, cache_key)
      cached_image.save
    end
  end
end
