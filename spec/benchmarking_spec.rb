# frozen_string_literal: true

require_relative '../lib/benchmarking'

RSpec.describe Benchmarking do
  describe '.duration' do
    it 'returns the result and duration' do
      result, duration = described_class.duration { 'hello' }

      expect(result).to eq('hello')
      expect(duration).to be_a(Float)
    end

    it 'measures the duration of the block' do
      _, duration = described_class.duration { sleep 0.1 }

      expect(duration).to be >= 0.1
    end
  end
end
