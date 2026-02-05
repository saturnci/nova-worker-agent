# frozen_string_literal: true

require_relative '../../../lib/executor'
require_relative '../../../lib/adapters/rails_rspec/worker'

RSpec.describe Adapters::RailsRSpec::Worker do
  describe '#docker_compose_project_name' do
    context 'when task_id is a non-empty string' do
      # WEAKNESS 1: instance_double wouldn't catch missing methods on Executor
      # WEAKNESS 2: duplicated setup (executor/worker defined in each context)
      let!(:executor) { instance_double(Executor, task_id: '123') }
      let!(:worker) { Adapters::RailsRSpec::Worker.new(executor) }

      it 'returns "task-" followed by the task_id' do
        expect(worker.docker_compose_project_name).to eq('task-123')
      end
    end

    context 'when task_id is empty' do
      # WEAKNESS 2: duplicated setup (executor/worker defined in each context)
      let!(:executor) { instance_double(Executor, task_id: '') }
      let!(:worker) { Adapters::RailsRSpec::Worker.new(executor) }

      it 'raises an error' do
        expect { worker.docker_compose_project_name }.to raise_error('task_id is empty')
      end
    end
  end

  describe '#send_results' do
    let!(:executor) do
      Executor.new(
        host: 'https://api.example.com',
        client: nil,
        worker_id: nil,
        task_id: '123'
      )
    end

    let!(:worker) { Adapters::RailsRSpec::Worker.new(executor) }

    before do
      allow(worker).to receive(:puts)
      allow(Executor).to receive(:project_dir).and_return('/repository')
    end

    # WEAKNESS 3: testing private method directly via send()
    # WEAKNESS 4: mock-heavy test verifies method calls rather than behavior
    it 'uploads json_output.json to the json_output endpoint' do
      request = instance_double(SaturnCIWorkerAPI::FileContentRequest)
      response = instance_double('Response', code: '200', body: '')

      expect(SaturnCIWorkerAPI::FileContentRequest).to receive(:new).with(
        host: 'https://api.example.com',
        api_path: 'tasks/123/json_output',
        content_type: 'application/json',
        file_path: '/repository/tmp/json_output.json'
      ).and_return(request)
      expect(request).to receive(:execute).and_return(response)

      worker.send(:send_results)
    end
  end
end
