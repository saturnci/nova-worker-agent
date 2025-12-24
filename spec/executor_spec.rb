# frozen_string_literal: true

require_relative '../lib/executor'

RSpec.describe Executor do
  describe '#compute_cache_key' do
    let!(:executor) { Executor.allocate }

    before do
      allow(Executor).to receive(:project_dir).and_return('/repository')
    end

    context 'when Gemfile.lock and Dockerfile exist' do
      before do
        allow(File).to receive(:read).with('/repository/Gemfile.lock').and_return('gem content')
        allow(File).to receive(:read).with('/repository/.saturnci/Dockerfile').and_return('dockerfile content')
      end

      it 'returns a 16-character hash' do
        expect(executor.compute_cache_key.length).to eq(16)
      end

      it 'returns consistent hash for same content' do
        key1 = executor.compute_cache_key
        key2 = executor.compute_cache_key
        expect(key1).to eq(key2)
      end
    end

    context 'when Gemfile.lock changes' do
      it 'returns different hash' do
        allow(File).to receive(:read).with('/repository/.saturnci/Dockerfile').and_return('dockerfile')

        allow(File).to receive(:read).with('/repository/Gemfile.lock').and_return('version 1')
        key1 = executor.compute_cache_key

        allow(File).to receive(:read).with('/repository/Gemfile.lock').and_return('version 2')
        key2 = executor.compute_cache_key

        expect(key1).not_to eq(key2)
      end
    end

    context 'when files do not exist' do
      before do
        allow(File).to receive(:read).and_raise(Errno::ENOENT)
      end

      it 'returns a hash based on empty strings' do
        expect(executor.compute_cache_key).to be_a(String)
        expect(executor.compute_cache_key.length).to eq(16)
      end
    end
  end

  describe '#shared_cache_dir' do
    it 'returns path based on repository ID' do
      allow(ENV).to receive(:fetch).with('REPOSITORY_ID').and_return('repo-123')
      executor = Executor.allocate
      expect(executor.shared_cache_dir).to eq('/shared/repo-123')
    end
  end

  describe '#cached_image_path' do
    it 'returns path to image.tar' do
      executor = Executor.allocate
      allow(executor).to receive(:shared_cache_dir).and_return('/shared/repo-123')
      expect(executor.cached_image_path).to eq('/shared/repo-123/image.tar')
    end
  end

  describe '#load_cached_image' do
    let!(:executor) { Executor.allocate }
    let!(:cached_image) { instance_double(Executor::CachedDockerImage) }
    let!(:cache_key) { 'abc123def456' }

    context 'when cached image exists' do
      before do
        allow(executor).to receive(:cached_image_path).and_return('/shared/repo-123/image.tar')
        allow(executor).to receive(:compute_cache_key).and_return(cache_key)
        allow(Executor::CachedDockerImage).to receive(:new)
          .with(image_name: 'my-image:latest', cache_path: '/shared/repo-123/image.tar', cache_key: cache_key)
          .and_return(cached_image)
        allow(cached_image).to receive(:load).and_return(true)
        allow(executor).to receive(:system).and_return(true)
        allow(executor).to receive(:puts)
        allow(executor).to receive(:send_worker_event)
      end

      it 'loads the image and returns true' do
        expect(executor.load_cached_image('my-image:latest')).to be true
      end

      it 'delegates to CachedDockerImage with cache key' do
        expect(Executor::CachedDockerImage).to receive(:new)
          .with(image_name: 'my-image:latest', cache_path: '/shared/repo-123/image.tar', cache_key: cache_key)
        executor.load_cached_image('my-image:latest')
      end
    end

    context 'when cached image does not exist' do
      before do
        allow(executor).to receive(:cached_image_path).and_return('/shared/repo-123/image.tar')
        allow(executor).to receive(:compute_cache_key).and_return(cache_key)
        allow(Executor::CachedDockerImage).to receive(:new).and_return(cached_image)
        allow(cached_image).to receive(:load).and_return(false)
        allow(executor).to receive(:puts)
        allow(executor).to receive(:send_worker_event)
      end

      it 'returns false' do
        expect(executor.load_cached_image('my-image:latest')).to be false
      end
    end
  end

  describe '#save_image_to_cache' do
    let!(:executor) { Executor.allocate }
    let!(:cached_image) { instance_double(Executor::CachedDockerImage) }
    let!(:cache_key) { 'abc123def456' }

    before do
      allow(executor).to receive(:cached_image_path).and_return('/shared/repo-123/image.tar')
      allow(executor).to receive(:compute_cache_key).and_return(cache_key)
      allow(Executor::CachedDockerImage).to receive(:new)
        .with(image_name: 'my-image:latest', cache_path: '/shared/repo-123/image.tar', cache_key: cache_key)
        .and_return(cached_image)
      allow(cached_image).to receive(:save)
    end

    it 'delegates to CachedDockerImage with cache key' do
      expect(Executor::CachedDockerImage).to receive(:new)
        .with(image_name: 'my-image:latest', cache_path: '/shared/repo-123/image.tar', cache_key: cache_key)
      executor.save_image_to_cache('my-image:latest')
    end
  end

  describe '#preload_app_image' do
    let!(:executor) { Executor.allocate }
    let!(:cache_key) { 'abc123def456' }

    before do
      allow(executor).to receive(:puts)
      allow(executor).to receive(:send_worker_event)
      allow(executor).to receive(:compute_cache_key).and_return(cache_key)
    end

    context 'when cached image exists' do
      before do
        allow(executor).to receive(:load_cached_image).with("saturnci-local:#{cache_key}").and_return(true)
        allow(executor).to receive(:system)
      end

      it 'loads from cache and returns true' do
        expect(executor.preload_app_image).to be true
      end

      it 'does not build' do
        expect(executor).not_to receive(:capture_and_stream_output)
        executor.preload_app_image
      end

      it 'tags the image as saturnci-local' do
        expect(executor).to receive(:system).with("docker tag saturnci-local:#{cache_key} saturnci-local")
        executor.preload_app_image
      end
    end

    context 'when cached image does not exist' do
      before do
        allow(executor).to receive(:load_cached_image).and_return(false)
        allow(executor).to receive(:capture_and_stream_output).and_return(['', true])
        allow(executor).to receive(:save_image_to_cache)
        allow(executor).to receive(:system)
      end

      it 'builds with docker build using tagged image name' do
        expect(executor).to receive(:capture_and_stream_output).with(/docker build.*-t saturnci-local:#{cache_key}/)
        executor.preload_app_image
      end

      it 'saves image to cache after successful build' do
        expect(executor).to receive(:save_image_to_cache).with("saturnci-local:#{cache_key}")
        executor.preload_app_image
      end

      it 'tags the image as saturnci-local' do
        expect(executor).to receive(:system).with("docker tag saturnci-local:#{cache_key} saturnci-local")
        executor.preload_app_image
      end
    end
  end
end
