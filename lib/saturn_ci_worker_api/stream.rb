# frozen_string_literal: true

require 'base64'
require_relative 'request'

module SaturnCIWorkerAPI
  WAIT_INTERVAL_IN_SECONDS = 5

  class Stream
    def initialize(log_file_path, api_path, wait_interval: WAIT_INTERVAL_IN_SECONDS)
      @log_file_path = log_file_path
      @api_path = api_path
      @keep_alive = true
      @wait_interval = wait_interval
    end

    def start
      @thread = Thread.new do
        most_recent_total_line_count = 0
        sent_content = []

        loop do
          all_lines = log_file_content
          newest_content = all_lines[most_recent_total_line_count..].join("\n")

          if newest_content.length.positive?
            send_content(newest_content)
            sent_content << newest_content
          end

          most_recent_total_line_count = all_lines.count

          sleep(@wait_interval)
          break unless @keep_alive
        end

        sent_content
      end
    end

    def kill
      @keep_alive = false
      @thread.join
    end

    def send_content(newest_content)
      SaturnCIWorkerAPI::Request.new(
        host: ENV.fetch('SATURNCI_API_HOST', nil),
        method: :post,
        endpoint: @api_path,
        content_type: 'text/plain',
        body: Base64.encode64("#{newest_content}\n")
      ).execute
    end

    def log_file_content
      File.readlines(@log_file_path)
    end
  end
end
