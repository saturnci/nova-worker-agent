# frozen_string_literal: true

require_relative '../../lib/saturn_ci_worker_api/request'

require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

describe SaturnCIWorkerAPI::Request do
  let(:host) { 'https://app.saturnci.com' }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WORKER_ID').and_return('worker_id')
    allow(ENV).to receive(:[]).with('WORKER_ACCESS_TOKEN').and_return('test_token')
  end

  context 'response is 5XX' do
    context '5XX error is fleeting' do
      it 'retries and then returns success when subsequent request succeeds' do
        stub_request(:get, 'https://app.saturnci.com/api/v1/worker_agents/workers/123')
          .to_return(
            { status: 503, body: 'Service Unavailable' },
            { status: 200, body: { 'id' => '123' }.to_json }
          )

        request = SaturnCIWorkerAPI::Request.new(
          host: host,
          method: :get,
          endpoint: 'workers/123'
        )

        response = request.execute

        expect(response.code).to eq('200')
      end
    end

    context '5XX error is persistent' do
      it 'gives up after 5 retries and returns the 5XX response code' do
        stub_request(:get, 'https://app.saturnci.com/api/v1/worker_agents/workers/123')
          .to_return(status: 503, body: 'Service Unavailable')

        request = SaturnCIWorkerAPI::Request.new(
          host: host,
          method: :get,
          endpoint: 'workers/123'
        )

        response = request.execute

        expect(response.code).to eq('503')
      end
    end
  end
end
