# frozen_string_literal: true

class TestSuiteResult
  attr_reader :examples

  def initialize(data)
    @data = data
    @examples = data['examples']
  end

  def merged_with(retry_result)
    new_examples = examples.map do |example|
      retry_result.example_by_id(example['id']) || example
    end

    new_data = @data.merge(
      'examples' => new_examples,
      'summary' => build_summary(new_examples),
      'summary_line' => build_summary_line(new_examples)
    )

    TestSuiteResult.new(new_data)
  end

  def example_by_id(id)
    examples.find { |example| example['id'] == id }
  end

  def example_count
    examples.size
  end

  def failure_count
    examples.count { |example| example['status'] == 'failed' }
  end

  def pending_count
    examples.count { |example| example['status'] == 'pending' }
  end

  def to_json(*_args)
    JSON.pretty_generate(@data)
  end

  private

  def build_summary(examples)
    @data['summary'].merge(
      'example_count' => examples.size,
      'failure_count' => examples.count { |example| example['status'] == 'failed' },
      'pending_count' => examples.count { |example| example['status'] == 'pending' }
    )
  end

  def build_summary_line(examples)
    failure_count = examples.count { |example| example['status'] == 'failed' }
    pending_count = examples.count { |example| example['status'] == 'pending' }
    "#{examples.size} examples, #{failure_count} failures, #{pending_count} pending"
  end
end
