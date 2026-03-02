require "test_helper"

class ObservableTest < ActiveSupport::TestCase
  setup do
    Setting.set(
      "proposer.low_level_bot_signatures",
      Observable::DEFAULT_LOW_LEVEL_BOT_SIGNATURES.join("\n")
    )
    Setting.invalidate_cache!
  end

  test "low_level_bot_scan_noise? true for commodity web probe with 404" do
    o = Observable.new(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - [26/Feb/2026:10:00:00 +0000] "GET /wp-login.php HTTP/1.1" 404 153 "-" "curl/8.0"',
      normalized_description: "Repeated probe for wp-login.php returned 404",
      observed_at: Time.current
    )

    assert o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? false when status is successful" do
    o = Observable.new(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - [26/Feb/2026:10:00:00 +0000] "GET /wp-login.php HTTP/1.1" 200 900 "-" "Mozilla/5.0"',
      normalized_description: "Request to wp-login.php succeeded",
      observed_at: Time.current
    )

    assert_not o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? false for non-web source" do
    o = Observable.new(
      source_type: "auth",
      raw_data: "Failed password for root from 10.0.0.10 port 22 ssh2",
      normalized_description: "SSH failed login for root",
      observed_at: Time.current
    )

    assert_not o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? uses configurable signature list" do
    Setting.set("proposer.low_level_bot_signatures", "/custom-bot-probe")
    o = Observable.new(
      source_type: "apache",
      raw_data: '5.6.7.8 - - [26/Feb/2026:10:00:00 +0000] "GET /custom-bot-probe HTTP/1.1" 404 10 "-" "-"',
      normalized_description: "Custom probe returned 404",
      observed_at: Time.current
    )

    assert o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? matches non-web signatures like sshd" do
    Setting.set("proposer.low_level_bot_signatures", "sshd")
    o = Observable.new(
      source_type: "syslog",
      raw_data: "2026-02-26T11:39:47Z host sshd[123]: Connection closed by 92.118.39.56",
      normalized_description: nil,
      observed_at: Time.current
    )

    assert o.low_level_bot_scan_noise?
  end

  test "prefiltered? true for normalizer prefilter stage" do
    o = Observable.new(
      source_type: "syslog",
      raw_data: "x",
      observed_at: Time.current,
      metadata: {
        "proposer_skip_reason" => "low_level_bot_scan_noise",
        "noise_filter_stage" => "normalizer_pre"
      }
    )
    assert o.l1_ks_prefiltered?
    assert o.prefiltered?
  end

  test "prefiltered? true for proposer filter stage" do
    o = Observable.new(
      source_type: "syslog",
      raw_data: "x",
      observed_at: Time.current,
      metadata: {
        "proposer_skip_reason" => "low_level_bot_scan_noise",
        "noise_filter_stage" => "proposer"
      }
    )
    assert o.proposer_prefiltered?
    assert o.prefiltered?
  end

  test "prefiltered? false for other skip reasons" do
    o = Observable.new(
      source_type: "syslog",
      raw_data: "x",
      observed_at: Time.current,
      metadata: { "proposer_skip_reason" => "max_attempts_reached", "noise_filter_stage" => "proposer" }
    )
    assert_not o.l1_ks_prefiltered?
    assert_not o.proposer_prefiltered?
    assert_not o.prefiltered?
  end

  # --- Error handling / edge-case tests ---

  test "low_level_bot_scan_noise? handles nil normalized_description" do
    o = Observable.new(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - [26/Feb/2026] "GET /wp-login.php HTTP/1.1" 404 10 "-" "-"',
      normalized_description: nil,
      observed_at: Time.current
    )
    # Should not raise; raw_data alone is enough for matching
    assert_nothing_raised { o.low_level_bot_scan_noise? }
    assert o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? handles nil source_type" do
    o = Observable.new(
      source_type: nil,
      raw_data: "some random non-matching log entry",
      observed_at: Time.current
    )
    # nil.to_s = "" so no web/apache/nginx match → non-web path
    assert_nothing_raised { o.low_level_bot_scan_noise? }
    assert_not o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? false when no signatures match" do
    o = Observable.new(
      source_type: "webserver",
      raw_data: '1.2.3.4 - - [26/Feb/2026] "GET /totally-normal-page.html HTTP/1.1" 404 10 "-" "-"',
      normalized_description: "Normal 404",
      observed_at: Time.current
    )
    assert_not o.low_level_bot_scan_noise?
  end

  test "low_level_bot_signatures falls back to defaults when setting is blank string" do
    Setting.set("proposer.low_level_bot_signatures", "")
    Setting.invalidate_cache!
    sigs = Observable.low_level_bot_signatures
    assert_equal Observable::DEFAULT_LOW_LEVEL_BOT_SIGNATURES, sigs
  end

  test "low_level_bot_signatures falls back to defaults when setting has only blank lines" do
    Setting.set("proposer.low_level_bot_signatures", "\n   \n\t\n")
    Setting.invalidate_cache!
    sigs = Observable.low_level_bot_signatures
    assert_equal Observable::DEFAULT_LOW_LEVEL_BOT_SIGNATURES, sigs
  end

  test "low_level_bot_signatures strips blank lines but keeps valid patterns" do
    Setting.set("proposer.low_level_bot_signatures", "\n/custom-path\n\n")
    Setting.invalidate_cache!
    sigs = Observable.low_level_bot_signatures
    assert_equal ["/custom-path"], sigs
  end

  test "prefilter_stage returns nil when metadata is nil" do
    o = Observable.new(source_type: "syslog", raw_data: "x", observed_at: Time.current, metadata: nil)
    assert_nil o.prefilter_stage
  end

  test "prefilter_stage returns nil when metadata is not a Hash" do
    o = Observable.new(source_type: "syslog", raw_data: "x", observed_at: Time.current)
    o.metadata = "not-a-hash"
    assert_nil o.prefilter_stage
  end

  test "l1_ks_prefiltered? false when metadata is nil" do
    o = Observable.new(source_type: "syslog", raw_data: "x", observed_at: Time.current, metadata: nil)
    assert_not o.l1_ks_prefiltered?
  end

  test "proposer_prefiltered? false when metadata is nil" do
    o = Observable.new(source_type: "syslog", raw_data: "x", observed_at: Time.current, metadata: nil)
    assert_not o.proposer_prefiltered?
  end

  test "prefiltered? false when metadata is empty hash" do
    o = Observable.new(source_type: "syslog", raw_data: "x", observed_at: Time.current, metadata: {})
    assert_not o.prefiltered?
  end

  test "low_level_bot_scan_noise? with non-web source returns true when signature matches" do
    Setting.set("proposer.low_level_bot_signatures", "badpattern")
    Setting.invalidate_cache!
    o = Observable.new(
      source_type: "syslog",
      raw_data: "2026-02-26T12:00:00Z host syslogd: badpattern detected",
      observed_at: Time.current
    )
    assert o.low_level_bot_scan_noise?
  end

  test "low_level_bot_scan_noise? returns false for web source with 200 even if signature matches" do
    o = Observable.new(
      source_type: "nginx",
      raw_data: '1.2.3.4 - - [26/Feb/2026] "GET /wp-login.php HTTP/1.1" 200 512 "-" "Mozilla"',
      observed_at: Time.current
    )
    assert_not o.low_level_bot_scan_noise?
  end
end
