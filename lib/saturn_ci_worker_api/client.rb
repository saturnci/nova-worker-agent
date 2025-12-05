# frozen_string_literal: true

require 'json'
require_relative 'request'

module SaturnCIWorkerAPI
  class Client
    def initialize(host)
      @host = host
    end

    def get(endpoint)
      Request.new(host: @host, method: :get, endpoint: endpoint).execute
    end

    def post(endpoint, payload = nil)
      Request.new(host: @host, method: :post, endpoint: endpoint, body: payload&.to_json).execute
    end

    def delete(endpoint)
      Request.new(host: @host, method: :delete, endpoint: endpoint).execute
    end

    def patch(endpoint, payload = nil)
      Request.new(host: @host, method: :patch, endpoint: endpoint, body: payload&.to_json).execute
    end

    def debug(message)
      post('debug_messages', message)
    end
  end
end
