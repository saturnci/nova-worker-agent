# frozen_string_literal: true

require_relative '../../../lib/executor'
require_relative '../../../lib/adapters/rails_rspec/follower_worker'

RSpec.describe Adapters::RailsRSpec::FollowerWorker do
  describe '#run' do
    let!(:executor) { instance_double(Executor) }
    let!(:worker) { described_class.new(executor) }

    before do
      allow(executor).to receive(:send_worker_event)
      allow(executor).to receive(:task_info).and_return({ 'run_order_index' => 2 })
      allow(executor).to receive(:wait_for_setup_complete)
      allow(worker).to receive(:clone_and_configure)
      allow(worker).to receive(:prepare_docker)
      allow(worker).to receive(:setup_database)
      allow(worker).to receive(:precompile_assets)
      allow(worker).to receive(:fetch_test_set)
      allow(worker).to receive(:execute_test_workflow)
      allow(worker).to receive(:puts)
    end

    it 'waits for setup complete and fetches test set before executing test workflow' do
      call_order = []

      allow(executor).to receive(:wait_for_setup_complete) { call_order << :wait_for_setup_complete }
      allow(worker).to receive(:fetch_test_set) { call_order << :fetch_test_set }
      allow(worker).to receive(:execute_test_workflow) { call_order << :execute_test_workflow }

      worker.run

      expect(call_order).to eq(%i[wait_for_setup_complete fetch_test_set execute_test_workflow])
    end
  end
end
