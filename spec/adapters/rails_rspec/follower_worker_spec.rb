# frozen_string_literal: true

require_relative '../../../lib/executor'
require_relative '../../../lib/adapters/rails_rspec/follower_worker'

describe Adapters::RailsRSpec::FollowerWorker do
  describe '#task_setup_completed?' do
    context 'setup is not yet complete' do
      it 'returns false' do
        client = double(get: double(body: '{"setup_completed": false}'))
        executor = double(task_id: '123', client: client)
        worker = Adapters::RailsRSpec::FollowerWorker.new(executor)

        expect(worker.task_setup_completed?).to be false
      end
    end

    context 'setup is complete' do
      it 'returns true' do
        client = double(get: double(body: '{"setup_completed": true}'))
        executor = double(task_id: '123', client: client)
        worker = Adapters::RailsRSpec::FollowerWorker.new(executor)

        expect(worker.task_setup_completed?).to be true
      end
    end
  end
end
