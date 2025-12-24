# frozen_string_literal: true

require_relative '../../../lib/executor'
require_relative '../../../lib/saturn_ci_worker_api_client'
require_relative '../../../lib/adapters/rails_rspec/follower_worker'

RSpec.describe Adapters::RailsRSpec::FollowerWorker do
  describe '#wait_for_setup_complete' do
    let!(:executor) { instance_double(Executor) }
    let!(:client) { instance_double(SaturnCIWorkerAPIClient) }
    let!(:worker) { described_class.allocate }

    before do
      worker.instance_variable_set(:@executor, executor)
      allow(executor).to receive(:client).and_return(client)
      allow(executor).to receive(:task_id).and_return('task-123')
      allow(worker).to receive(:puts)
      allow(worker).to receive(:sleep)
    end

    context 'when setup is already complete' do
      before do
        response = instance_double('Response', body: '{"setup_completed": true}')
        allow(client).to receive(:get).with('tasks/task-123').and_return(response)
      end

      it 'returns immediately' do
        expect(worker).not_to receive(:sleep)
        worker.send(:wait_for_setup_complete)
      end
    end

    context 'when setup completes after polling' do
      before do
        not_complete = instance_double('Response', body: '{"setup_completed": false}')
        complete = instance_double('Response', body: '{"setup_completed": true}')
        allow(client).to receive(:get).with('tasks/task-123').and_return(not_complete, not_complete, complete)
      end

      it 'polls until setup is complete' do
        expect(worker).to receive(:sleep).with(2).twice
        worker.send(:wait_for_setup_complete)
      end
    end
  end
end
