require "test_helper"

# Tests for NormalizerJob#prefilter_low_level_bot_scans (private method).
# Exercised via `send` to avoid setting up a full LLM pipeline.
class NormalizerJobPrefilterTest < ActiveSupport::TestCase
  setup do
    Setting.set("proposer.low_level_bot_signatures",
                Observable::DEFAULT_LOW_LEVEL_BOT_SIGNATURES.join("\n"))
    Setting.set("proposer.filter_low_level_bot_scans", true)
    Setting.invalidate_cache!
  end

  # Helper: insert a persisted observable using bulk insert to bypass all
  # after_create_commit callbacks (avoids NormalizerJob enqueue / Redis touch).
  def create_observable(source_type: "syslog", raw_data: "some log line", metadata: nil)
    now = Time.current
    result = Observable.insert(
      {
        source_type: source_type,
        raw_data: raw_data,
        observed_at: now,
        domain: "test",
        metadata: metadata,
        entity_extractions: {},
        created_at: now,
        updated_at: now
      },
      returning: [:id]
    )
    Observable.find(result.rows.first.first)
  end

  def job
    NormalizerJob.new
  end

  # --- Setting disabled ---

  test "returns [[], all_observables] when filter setting is disabled" do
    Setting.set("proposer.filter_low_level_bot_scans", false)
    Setting.invalidate_cache!

    obs = Observable.new(source_type: "webserver",
                         raw_data: '1.2.3.4 - - "GET /wp-login.php" 404',
                         observed_at: Time.current)
    filtered, to_normalize = job.send(:prefilter_low_level_bot_scans, [obs])

    assert_equal [], filtered
    assert_equal [obs], to_normalize
  end

  # --- Empty input ---

  test "returns [[], []] for empty observables array" do
    filtered, to_normalize = job.send(:prefilter_low_level_bot_scans, [])
    assert_equal [], filtered
    assert_equal [], to_normalize
  end

  # --- Matched observable (L1 bot scan) ---

  test "matched observable is placed in filtered list and metadata is stamped" do
    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /wp-login.php HTTP/1.1" 404 10'
    )

    filtered, to_normalize = job.send(:prefilter_low_level_bot_scans, [obs])

    assert_equal 1, filtered.length
    assert_equal 0, to_normalize.length

    obs.reload
    assert_equal "normalizer_pre", obs.metadata["noise_filter_stage"]
    assert obs.metadata["proposer_skipped"]
    assert_equal "low_level_bot_scan_noise", obs.metadata["proposer_skip_reason"]
    assert obs.metadata["l1_bot_filter"]["matched"]
    assert_equal "Filtered low-level bot scan noise", obs.normalized_description
  end

  # --- Unmatched observable ---

  test "unmatched observable is placed in to_normalize list and l1_bot_filter is stamped as not matched" do
    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /normal-page HTTP/1.1" 200 500'
    )

    filtered, to_normalize = job.send(:prefilter_low_level_bot_scans, [obs])

    assert_equal 0, filtered.length
    assert_equal 1, to_normalize.length

    obs.reload
    assert_equal false, obs.metadata["l1_bot_filter"]["matched"]
    assert_nil obs.metadata["noise_filter_stage"]
  end

  # --- Mixed batch ---

  test "correctly partitions a mixed batch of matched and unmatched observables" do
    bot_obs = create_observable(
      source_type: "nginx",
      raw_data: '5.5.5.5 - - "GET /wp-login.php HTTP/1.1" 403 0'
    )
    normal_obs = create_observable(
      source_type: "nginx",
      raw_data: '6.6.6.6 - - "GET /index.html HTTP/1.1" 200 1024'
    )

    filtered, to_normalize = job.send(:prefilter_low_level_bot_scans, [bot_obs, normal_obs])

    assert_equal [bot_obs.id], filtered.map(&:id)
    assert_equal [normal_obs.id], to_normalize.map(&:id)
  end

  # --- DB error on matched observable ---

  test "raises when update_columns fails for a matched observable" do
    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /wp-login.php HTTP/1.1" 404 10'
    )
    # Define singleton method so AR method_missing doesn't intercept
    def obs.update_columns(*)
      raise ActiveRecord::ActiveRecordError, "DB unavailable"
    end

    assert_raises(ActiveRecord::ActiveRecordError) do
      job.send(:prefilter_low_level_bot_scans, [obs])
    end
  end

  # --- DB error on unmatched observable ---

  test "raises when update_columns fails for an unmatched observable" do
    obs = create_observable(
      source_type: "nginx",
      raw_data: '1.2.3.4 - - "GET /index.html HTTP/1.1" 200 800'
    )
    def obs.update_columns(*)
      raise ActiveRecord::ActiveRecordError, "DB unavailable"
    end

    assert_raises(ActiveRecord::ActiveRecordError) do
      job.send(:prefilter_low_level_bot_scans, [obs])
    end
  end

  # --- Exception from low_level_bot_scan_noise? ---

  test "raises when low_level_bot_scan_noise? raises for an observable" do
    obs = create_observable(source_type: "syslog", raw_data: "some line")
    def obs.low_level_bot_scan_noise?
      raise RuntimeError, "signature lookup failed"
    end

    assert_raises(RuntimeError) do
      job.send(:prefilter_low_level_bot_scans, [obs])
    end
  end

  # --- Non-web observable ---

  test "non-web observable matching a configured signature is filtered at L1" do
    Setting.set("proposer.low_level_bot_signatures", "known-bot-pattern")
    Setting.invalidate_cache!

    obs = create_observable(
      source_type: "syslog",
      raw_data: "2026-02-26T12:00:00Z host syslogd: known-bot-pattern connection attempt"
    )

    filtered, to_normalize = job.send(:prefilter_low_level_bot_scans, [obs])

    assert_equal 1, filtered.length
    assert_equal 0, to_normalize.length
  end
end
