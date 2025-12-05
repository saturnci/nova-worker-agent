# frozen_string_literal: true

require 'net/http'
require 'uri'
require_relative 'api_config'

module SaturnCIWorkerAPI
  class Request
    include APIConfig

    MAX_RETRY_COUNT = 5

    def initialize(host:, endpoint:, method:, body: nil, content_type: 'application/json', headers: {})
      @host = host
      @endpoint = endpoint
      @method = method
      @body = body
      @content_type = content_type
      @headers = headers
    end

    def execute
      retry_count = 0

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true if url.scheme == 'https'

      loop do
        response = http.request(request)

        if response.code.start_with?('5')
          retry_count += 1
          return response if retry_count > MAX_RETRY_COUNT

          sleep(ENV.fetch('RETRY_INTERVAL_IN_SECONDS', 1).to_i)
          next
        end

        break response
      end
    end

    def request
      case @method
      when :get
        r = Net::HTTP::Get.new(url)
      when :post
        r = Net::HTTP::Post.new(url)
      when :delete
        r = Net::HTTP::Delete.new(url)
      when :patch
        r = Net::HTTP::Patch.new(url)
      end

      r.basic_auth(ENV.fetch('WORKER_ID', nil), ENV.fetch('WORKER_ACCESS_TOKEN', nil))
      r['Content-Type'] = @content_type
      @headers.each { |key, value| r[key] = value }
      r.body = @body
      r
    end

    private

    def url
      URI("#{@host}#{API_BASE_PATH}/#{@endpoint}")
    end
  end
end
