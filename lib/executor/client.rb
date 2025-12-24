# frozen_string_literal: true

require 'json'
require_relative '../saturn_ci_worker_api/request'

class Executor
  class Client
    def initialize(host:)
      @host = host
    end

    def get(endpoint)
      request(:get, endpoint)
    end

    def post(endpoint, body = nil)
      request(:post, endpoint, body)
    end

    private

    def request(method, endpoint, body = nil)
      SaturnCIWorkerAPI::Request.new(
        host: @host,
        method: method,
        endpoint: endpoint,
        body: body&.to_json
      ).execute
    end
  end
end
