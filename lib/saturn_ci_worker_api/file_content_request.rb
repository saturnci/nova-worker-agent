# frozen_string_literal: true

require_relative 'request'

module SaturnCIWorkerAPI
  class FileContentRequest
    def initialize(host:, api_path:, content_type:, file_path:)
      @host = host
      @api_path = api_path
      @content_type = content_type
      @file_path = file_path
    end

    def execute
      Request.new(
        host: @host,
        endpoint: @api_path,
        method: :post,
        body: File.read(@file_path),
        content_type: @content_type,
        headers: { 'X-Filename' => File.basename(@file_path) }
      ).execute
    end
  end
end
