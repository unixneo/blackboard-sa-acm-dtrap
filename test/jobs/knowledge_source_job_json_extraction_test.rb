# frozen_string_literal: true

require "test_helper"

# Minimal host that includes the shared concern so we can call private helpers.
class JsonExtractionHost
  include LlmPipelineMethods
end

class KnowledgeSourceJobJsonExtractionTest < ActiveSupport::TestCase
  setup do
    @job = JsonExtractionHost.new
  end

  # Test case 1: Deeply nested object with prose wrapping
  test "extract_json_object handles deeply nested JSON with surrounding prose" do
    response = <<~RESPONSE
      Here is the result:

      {
        "hypothesis": {
          "confidence": 0.82,
          "evidence": [
            {"ip": "1.2.3.4", "geo": {"country": "RU"}}
          ]
        }
      }

      Additional commentary below.
    RESPONSE

    result = @job.send(:extract_json_object, response)

    assert_equal 0.82, result.dig("hypothesis", "confidence")
    assert_equal "1.2.3.4", result.dig("hypothesis", "evidence", 0, "ip")
    assert_equal "RU", result.dig("hypothesis", "evidence", 0, "geo", "country")
  end

  # Test case 2: Nested arrays with prose wrapping
  test "extract_json_array handles nested arrays with surrounding prose" do
    response = <<~RESPONSE
      Some intro text
      [
        {"a": 1, "b": {"c": [1,2,3]}}
      ]
      More trailing text.
    RESPONSE

    result = @job.send(:extract_json_array, response)

    assert_instance_of Array, result
    assert_equal 1, result.length
    assert_equal 1, result[0]["a"]
    assert_equal [1, 2, 3], result[0]["b"]["c"]
  end

  # Test balanced extraction with strings containing brackets
  test "extract_balanced_json handles brackets inside strings" do
    response = <<~RESPONSE
      Here's the data:
      {"message": "Use [brackets] and {braces} freely", "count": 5}
      Done.
    RESPONSE

    result = @job.send(:extract_json_object, response)

    assert_equal "Use [brackets] and {braces} freely", result["message"]
    assert_equal 5, result["count"]
  end

  # Test escaped quotes inside strings
  test "extract_balanced_json handles escaped quotes" do
    response = %q{{"text": "He said \"hello\" to me", "valid": true}}

    result = @job.send(:extract_json_object, response)

    assert_equal 'He said "hello" to me', result["text"]
    assert_equal true, result["valid"]
  end

  # Classic escape-state trap: backslash-quote sequence
  # The string contains: backslash then quote: \" (literal backslash followed by quote)
  # JSON encoding: \\\" = escaped backslash + escaped quote
  test "extract_balanced_json handles backslash-quote escape trap" do
    # This is the nasty case: {"s":"backslash then quote: \\\", still in string", "x":1}
    response = '{"s":"backslash then quote: \\\\\\", still in string", "x":1}'

    result = @job.send(:extract_json_object, response)

    assert_equal 'backslash then quote: \\", still in string', result["s"]
    assert_equal 1, result["x"]
  end

  # Test empty cases
  test "extract_json_object returns empty hash for blank input" do
    assert_equal({}, @job.send(:extract_json_object, nil))
    assert_equal({}, @job.send(:extract_json_object, ""))
    assert_equal({}, @job.send(:extract_json_object, "   "))
  end

  test "extract_json_array returns empty array for blank input" do
    assert_equal([], @job.send(:extract_json_array, nil))
    assert_equal([], @job.send(:extract_json_array, ""))
    assert_equal([], @job.send(:extract_json_array, "   "))
  end

  # Test code block extraction
  test "extract_json_object handles code blocks" do
    response = <<~RESPONSE
      Here's the JSON:
      ```json
      {"key": "value", "nested": {"deep": true}}
      ```
      That's all.
    RESPONSE

    result = @job.send(:extract_json_object, response)

    assert_equal "value", result["key"]
    assert_equal true, result.dig("nested", "deep")
  end

  # Test pure JSON (no prose)
  test "extract_json_object handles pure JSON input" do
    response = '{"direct": "json", "no": "prose"}'

    result = @job.send(:extract_json_object, response)

    assert_equal "json", result["direct"]
    assert_equal "prose", result["no"]
  end

  test "extract_json_array handles pure JSON input" do
    response = '[{"item": 1}, {"item": 2}]'

    result = @job.send(:extract_json_array, response)

    assert_equal 2, result.length
    assert_equal 1, result[0]["item"]
    assert_equal 2, result[1]["item"]
  end
end
