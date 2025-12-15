# frozen_string_literal: true

require 'benchmark'

module Benchmarking
  def self.duration
    result = nil
    time = Benchmark.realtime { result = yield }
    [result, time.round(1)]
  end
end
