# frozen_string_literal: true

require_relative '../../lib/saturn_ci_worker_api/client'

require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

describe SaturnCIWorkerAPI::Client do
  let(:host) { 'https://app.saturnci.com' }
  let(:client) { SaturnCIWorkerAPI::Client.new(host) }

  before do
    ENV['WORKER_ID'] = 'worker_id'
    ENV['WORKER_ACCESS_TOKEN'] = 'test_token'
  end

  describe '#get' do
    before do
      stub_request(:get, 'https://app.saturnci.com/api/v1/worker_agents/workers/123/assignments')
        .to_return(status: 200, body: [{ run_id: 'abc' }].to_json)
    end

    it 'makes a GET request and returns the response' do
      response = client.get('workers/123/assignments')
      expect(response.code).to eq('200')
      expect(JSON.parse(response.body)).to eq([{ 'run_id' => 'abc' }])
    end
  end
end
