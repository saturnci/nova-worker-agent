# frozen_string_literal: true

require_relative '../lib/saturn_ci_worker_api_client'

RSpec.describe SaturnCIWorkerAPIClient do
  let(:host) { 'http://localhost:3000' }
  let(:client) { described_class.new(host: host) }

  describe '#get' do
    it 'makes a GET request to the endpoint' do
      request = instance_double(SaturnCIWorkerAPI::Request)
      expect(SaturnCIWorkerAPI::Request).to receive(:new).with(
        host: host,
        method: :get,
        endpoint: 'tasks/123',
        body: nil
      ).and_return(request)
      expect(request).to receive(:execute)

      client.get('tasks/123')
    end
  end

  describe '#post' do
    context 'without body' do
      it 'makes a POST request to the endpoint' do
        request = instance_double(SaturnCIWorkerAPI::Request)
        expect(SaturnCIWorkerAPI::Request).to receive(:new).with(
          host: host,
          method: :post,
          endpoint: 'tasks/123/events',
          body: nil
        ).and_return(request)
        expect(request).to receive(:execute)

        client.post('tasks/123/events')
      end
    end

    context 'with body' do
      it 'makes a POST request with JSON body' do
        request = instance_double(SaturnCIWorkerAPI::Request)
        expect(SaturnCIWorkerAPI::Request).to receive(:new).with(
          host: host,
          method: :post,
          endpoint: 'tasks/123/events',
          body: '{"type":"started"}'
        ).and_return(request)
        expect(request).to receive(:execute)

        client.post('tasks/123/events', { type: 'started' })
      end
    end
  end
end
