# frozen_string_literal: true

require_relative '../../lib/saturn_ci_worker_api/request'

require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

describe SaturnCIWorkerAPI::Request do
  let!(:host) { 'https://app.saturnci.com' }

  before do
    allow(ENV).to receive(:[]).with('WORKER_ID').and_return('worker_id')
    allow(ENV).to receive(:[]).with('WORKER_ACCESS_TOKEN').and_return('test_token')
  end

  describe 'GET request' do
    let!(:request) do
      SaturnCIWorkerAPI::Request.new(host: host, method: :get, endpoint: 'workers/123')
    end

    before do
      stub_request(:get, 'https://app.saturnci.com/api/v1/worker_agents/workers/123')
        .to_return(status: 200, body: { 'id' => '123' }.to_json)
    end

    it 'parses the response body as JSON' do
      response = request.execute
      expect(JSON.parse(response.body)).to eq({ 'id' => '123' })
    end
  end

  describe 'custom headers' do
    let!(:request) do
      SaturnCIWorkerAPI::Request.new(
        host: host,
        method: :post,
        endpoint: 'files',
        body: 'file content',
        headers: { 'X-Filename' => 'test.json' }
      )
    end

    before do
      stub_request(:post, 'https://app.saturnci.com/api/v1/worker_agents/files')
        .with(headers: { 'X-Filename' => 'test.json' })
        .to_return(status: 200, body: 'ok')
    end

    it 'includes custom headers in the request' do
      response = request.execute
      expect(response.body).to eq('ok')
    end
  end
end
