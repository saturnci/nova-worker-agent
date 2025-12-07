# frozen_string_literal: true

require_relative '../lib/test_suite_result'

RSpec.describe TestSuiteResult do
  describe '#merged_with' do
    it 'replaces a failed test with its passing retry result' do
      original = build_result([
                                { 'id' => 'test_1', 'status' => 'passed' },
                                { 'id' => 'test_2', 'status' => 'failed' }
                              ])

      retry_result = build_result([
                                    { 'id' => 'test_2', 'status' => 'passed' }
                                  ])

      merged = original.merged_with(retry_result)

      expect(merged.failure_count).to eq(0)
    end

    it 'keeps a test as failed if it fails on retry too' do
      original = build_result([
                                { 'id' => 'test_1', 'status' => 'passed' },
                                { 'id' => 'test_2', 'status' => 'failed' }
                              ])

      retry_result = build_result([
                                    { 'id' => 'test_2', 'status' => 'failed' }
                                  ])

      merged = original.merged_with(retry_result)

      expect(merged.failure_count).to eq(1)
    end

    it 'does not mutate the original result' do
      original = build_result([
                                { 'id' => 'test_1', 'status' => 'failed' }
                              ])

      retry_result = build_result([
                                    { 'id' => 'test_1', 'status' => 'passed' }
                                  ])

      original.merged_with(retry_result)

      expect(original.failure_count).to eq(1)
    end
  end

  def build_result(examples)
    TestSuiteResult.new(
      {
        'examples' => examples,
        'summary' => {}
      }
    )
  end
end
