# frozen_string_literal: true

require_relative '../lib/executor'

RSpec.describe Executor do
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

    context 'when cached image exists' do
      before do
        allow(executor).to receive(:cached_image_path).and_return('/shared/repo-123/image.tar')
        allow(File).to receive(:exist?).with('/shared/repo-123/image.tar').and_return(true)
        allow(File).to receive(:size).with('/shared/repo-123/image.tar').and_return(500_000_000)
        allow(executor).to receive(:system).and_return(true)
        allow(executor).to receive(:puts)
        allow(executor).to receive(:send_worker_event)
      end

      it 'loads the image and returns true' do
        expect(executor.load_cached_image('my-image:latest')).to be true
      end

      it 'runs docker load' do
        expect(executor).to receive(:system).with('docker load < /shared/repo-123/image.tar')
        executor.load_cached_image('my-image:latest')
      end
    end

    context 'when cached image does not exist' do
      before do
        allow(executor).to receive(:cached_image_path).and_return('/shared/repo-123/image.tar')
        allow(File).to receive(:exist?).with('/shared/repo-123/image.tar').and_return(false)
      end

      it 'returns false' do
        expect(executor.load_cached_image('my-image:latest')).to be false
      end
    end
  end

  describe '#save_image_to_cache' do
    let!(:executor) { Executor.allocate }

    before do
      allow(executor).to receive(:shared_cache_dir).and_return('/shared/repo-123')
      allow(executor).to receive(:cached_image_path).and_return('/shared/repo-123/image.tar')
      allow(FileUtils).to receive(:mkdir_p)
      allow(executor).to receive(:system).and_return(true)
      allow(executor).to receive(:puts)
    end

    it 'creates the cache directory' do
      expect(FileUtils).to receive(:mkdir_p).with('/shared/repo-123')
      executor.save_image_to_cache('my-image:latest')
    end

    it 'saves the image' do
      expect(executor).to receive(:system).with('docker save my-image:latest > /shared/repo-123/image.tar')
      executor.save_image_to_cache('my-image:latest')
    end
  end

  describe '#wait_for_setup_complete' do
    let!(:executor) { Executor.allocate }

    before do
      executor.instance_variable_set(:@host, 'http://localhost')
      executor.instance_variable_set(:@task_id, 'task-123')
      allow(executor).to receive(:puts)
      allow(executor).to receive(:sleep)
    end

    context 'when setup is already complete' do
      before do
        response = instance_double('Response', body: '{"setup_completed": true}')
        allow(SaturnCIWorkerAPI::Request).to receive(:new).and_return(
          instance_double('Request', execute: response)
        )
      end

      it 'returns immediately' do
        expect(executor).not_to receive(:sleep)
        executor.wait_for_setup_complete
      end
    end

    context 'when setup completes after polling' do
      before do
        not_complete = instance_double('Response', body: '{"setup_completed": false}')
        complete = instance_double('Response', body: '{"setup_completed": true}')
        request = instance_double('Request')
        allow(SaturnCIWorkerAPI::Request).to receive(:new).and_return(request)
        allow(request).to receive(:execute).and_return(not_complete, not_complete, complete)
      end

      it 'polls until setup is complete' do
        expect(executor).to receive(:sleep).with(2).twice
        executor.wait_for_setup_complete
      end
    end
  end

  describe '#build_with_cache' do
    let!(:executor) { Executor.allocate }
    let!(:registry_cache) { instance_double(SaturnCIWorkerAPI::DockerRegistryCache) }

    before do
      executor.instance_variable_set(
        :@task_info,
        {
          'docker_registry_cache_username' => 'user',
          'docker_registry_cache_password' => 'pass',
          'project_name' => 'myproject',
          'branch_name' => 'main'
        }
      )
      allow(SaturnCIWorkerAPI::DockerRegistryCache).to receive(:new).and_return(registry_cache)
      allow(registry_cache).to receive(:image_url).and_return('registry:5000/myproject')
      allow(executor).to receive(:puts)
      allow(executor).to receive(:send_worker_event)
    end

    context 'when cached image exists' do
      before do
        allow(executor).to receive(:load_cached_image).and_return(true)
      end

      it 'loads from cache and returns true' do
        expect(executor.build_with_cache).to be true
      end

      it 'does not authenticate to registry' do
        expect(registry_cache).not_to receive(:authenticate)
        executor.build_with_cache
      end
    end

    context 'when cached image does not exist' do
      before do
        allow(executor).to receive(:load_cached_image).and_return(false)
        allow(registry_cache).to receive(:authenticate).and_return(true)
        allow(executor).to receive(:system).and_return(true)
        allow(File).to receive(:write)
        allow(executor).to receive(:capture_and_stream_output).and_return(['', true])
        allow(executor).to receive(:save_image_to_cache)
      end

      it 'builds with buildx' do
        expect(executor).to receive(:capture_and_stream_output).with(/docker buildx build/)
        executor.build_with_cache
      end

      it 'saves image to cache after successful build' do
        expect(executor).to receive(:save_image_to_cache).with('registry:5000/myproject:latest')
        executor.build_with_cache
      end
    end
  end
end
