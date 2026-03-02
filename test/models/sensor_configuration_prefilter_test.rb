require "test_helper"

class SensorConfigurationPrefilterTest < ActiveSupport::TestCase
  def build_sensor(filter_patterns: [])
    SensorConfiguration.new(
      name: "test sensor",
      platform: "linux",
      source_type: "syslog",
      filter_patterns: filter_patterns
    )
  end

  # --- filters_line? happy-path tests ---

  test "filters_line? returns false when patterns list is empty" do
    sensor = build_sensor(filter_patterns: [])
    assert_not sensor.filters_line?("anything at all")
  end

  test "filters_line? returns true when line contains a pattern (case-insensitive)" do
    sensor = build_sensor(filter_patterns: ["healthcheck"])
    assert sensor.filters_line?("GET /healthcheck HTTP/1.1 200")
    assert sensor.filters_line?("GET /HEALTHCHECK HTTP/1.1 200")
  end

  test "filters_line? returns false when no pattern matches" do
    sensor = build_sensor(filter_patterns: ["healthcheck"])
    assert_not sensor.filters_line?("Failed password for root from 10.0.0.1")
  end

  test "filters_line? matches any of multiple patterns" do
    sensor = build_sensor(filter_patterns: ["healthcheck", "ping"])
    assert sensor.filters_line?("GET /ping HTTP/1.1 200")
    assert_not sensor.filters_line?("normal log line")
  end

  # --- filters_line? error / edge-case tests ---

  test "filters_line? returns false for empty string line" do
    sensor = build_sensor(filter_patterns: ["healthcheck"])
    assert_not sensor.filters_line?("")
  end

  test "filters_line? raises when line is nil (documents current behavior)" do
    sensor = build_sensor(filter_patterns: ["healthcheck"])
    # nil.downcase raises NoMethodError — callers must guard against nil lines
    assert_raises(NoMethodError) { sensor.filters_line?(nil) }
  end

  # --- filter_patterns_list edge cases ---

  test "filter_patterns_list returns empty array when filter_patterns is nil" do
    sensor = build_sensor
    sensor.filter_patterns = nil
    assert_equal [], sensor.filter_patterns_list
  end

  test "filter_patterns_list returns empty array when filter_patterns is empty array" do
    sensor = build_sensor(filter_patterns: [])
    assert_equal [], sensor.filter_patterns_list
  end

  test "filter_patterns_list coerces integer entries to strings" do
    sensor = build_sensor
    sensor.filter_patterns = [42, "health"]
    assert_equal ["42", "health"], sensor.filter_patterns_list
  end

  # --- normalize_filter_patterns (before_validation callback) ---

  test "normalize_filter_patterns strips blank entries from string input" do
    sensor = build_sensor
    sensor.filter_patterns = "healthcheck\n\n  \nping\n"
    sensor.valid?   # triggers before_validation
    assert_equal ["healthcheck", "ping"], sensor.filter_patterns
  end

  test "normalize_filter_patterns deduplicates patterns" do
    sensor = build_sensor
    sensor.filter_patterns = "healthcheck\nhealthcheck\nHealthCheck\n"
    sensor.valid?
    assert_equal ["healthcheck"], sensor.filter_patterns
  end

  test "normalize_filter_patterns downcases all patterns" do
    sensor = build_sensor
    sensor.filter_patterns = "HealthCheck\nPING"
    sensor.valid?
    assert_equal ["healthcheck", "ping"], sensor.filter_patterns
  end

  test "normalize_filter_patterns handles empty string gracefully" do
    sensor = build_sensor
    sensor.filter_patterns = ""
    sensor.valid?
    assert_equal [], sensor.filter_patterns
  end

  test "normalize_filter_patterns handles nil gracefully" do
    sensor = build_sensor
    sensor.filter_patterns = nil
    assert_nothing_raised { sensor.valid? }
    assert_equal [], sensor.filter_patterns
  end
end
