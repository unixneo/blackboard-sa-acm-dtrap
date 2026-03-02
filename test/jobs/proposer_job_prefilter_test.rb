require "test_helper"

# Tests for ProposerJob#apply_low_level_bot_prefilter! (private method).
# Exercised via `send` to avoid setting up a full LLM pipeline.
class ProposerJobPrefilterTest < ActiveSupport::TestCase
  setup do
    Setting.set("proposer.low_level_bot_signatures",
                Observable::DEFAULT_LOW_LEVEL_BOT_SIGNATURES.join("\n"))
    Setting.set("proposer.filter_low_level_bot_scans", true)
    Setting.invalidate_cache!
  end

  # Helper: insert a persisted observable using bulk insert to bypass all
  # after_create_commit callbacks (avoids NormalizerJob enqueue / Redis touch).
  def create_observable(source_type: "syslog", raw_data: "some log line",
                        normalized_description: "normalised log entry",
                        metadata: nil)
    now = Time.current
    result = Observable.insert(
      {
        source_type: source_type,
        raw_data: raw_data,
        normalized_description: normalized_description,
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

  # Wrap a single observable as an AR relation-like scope (find_each compatible)
  def scope_for(*observables)
    Observable.where(id: observables.map(&:id))
  end

  def job
    ProposerJob.new
  end

  # --- Setting disabled ---

  test "is a no-op when filter setting is disabled" do
    Setting.set("proposer.filter_low_level_bot_scans", false)
    Setting.invalidate_cache!

    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /wp-login.php HTTP/1.1" 404 10'
    )

    job.send(:apply_low_level_bot_prefilter!, scope_for(obs))

    obs.reload
    assert_nil obs.metadata
  end

  # --- Already-skipped observable ---

  test "skips an observable that is already marked proposer_skipped" do
    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /wp-login.php HTTP/1.1" 404 10',
      metadata: {
        "proposer_skipped" => true,
        "proposer_skip_reason" => "already_handled",
        "noise_filter_stage" => "normalizer_pre"
      }
    )

    job.send(:apply_low_level_bot_prefilter!, scope_for(obs))

    obs.reload
    # Stage should remain unchanged — the already-skipped guard must prevent overwrite
    assert_equal "normalizer_pre", obs.metadata["noise_filter_stage"]
    assert_equal "already_handled", obs.metadata["proposer_skip_reason"]
  end

  # --- Matching observable not yet skipped ---

  test "stamps metadata on a bot-scan observable that was not yet skipped" do
    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /wp-login.php HTTP/1.1" 404 10',
      normalized_description: "Probe for wp-login returned 404",
      metadata: nil
    )

    job.send(:apply_low_level_bot_prefilter!, scope_for(obs))

    obs.reload
    assert obs.metadata["proposer_skipped"]
    assert_equal "low_level_bot_scan_noise", obs.metadata["proposer_skip_reason"]
    assert_equal "proposer", obs.metadata["noise_filter_stage"]
  end

  # --- Non-matching observable ---

  test "leaves non-bot observable untouched" do
    obs = create_observable(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - "GET /index.html HTTP/1.1" 200 1024',
      normalized_description: "Normal page request returned 200",
      metadata: nil
    )

    job.send(:apply_low_level_bot_prefilter!, scope_for(obs))

    obs.reload
    assert_nil obs.metadata
  end

  # --- Mixed batch ---

  test "only stamps bot-scan observables within a mixed batch" do
    bot_obs = create_observable(
      source_type: "nginx",
      raw_data: '5.5.5.5 - - "GET /wp-login.php HTTP/1.1" 403 0',
      normalized_description: "Probe for wp-login returned 403"
    )
    normal_obs = create_observable(
      source_type: "nginx",
      raw_data: '6.6.6.6 - - "GET /api/health HTTP/1.1" 200 30',
      normalized_description: "Health check returned 200"
    )

    job.send(:apply_low_level_bot_prefilter!, scope_for(bot_obs, normal_obs))

    bot_obs.reload
    normal_obs.reload

    assert bot_obs.proposer_prefiltered?
    assert_nil normal_obs.metadata
  end

  # --- Empty scope ---

  test "handles an empty observable scope without error" do
    empty_scope = Observable.where(id: [])
    assert_nothing_raised { job.send(:apply_low_level_bot_prefilter!, empty_scope) }
  end
end
