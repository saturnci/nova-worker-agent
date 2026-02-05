# frozen_string_literal: true

require_relative '../../../lib/executor'
require_relative '../../../lib/adapters/rails_rspec/worker'

RSpec.describe Adapters::RailsRSpec::Worker do
  describe '#docker_compose_project_name' do
    context 'when task_id is a non-empty string' do
      let!(:executor) { instance_double(Executor, task_id: '123') }
      let!(:worker) { Adapters::RailsRSpec::Worker.new(executor) }

      it 'returns "task-" followed by the task_id' do
        expect(worker.docker_compose_project_name).to eq('task-123')
      end
    end

    context 'when task_id is empty' do
      let!(:executor) { instance_double(Executor, task_id: '') }
      let!(:worker) { Adapters::RailsRSpec::Worker.new(executor) }

      it 'raises an error' do
        expect { worker.docker_compose_project_name }.to raise_error('task_id is empty')
      end
    end
  end
end
