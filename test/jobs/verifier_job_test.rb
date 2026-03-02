# frozen_string_literal: true

require "test_helper"

class VerifierJobTestDouble < VerifierJob
  cattr_accessor :test_payload

  private

  def call_llm(_prompt, max_tokens:, items_count: 1)
    "stubbed-response"
  end

  def parse_verification_response(_response)
    [self.class.test_payload, false]
  end
end

class VerifierJobTest < ActiveJob::TestCase
  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "halts additional verification creation after hypothesis leaves critiqued status" do
    KnowledgeSource.create!(
      name: "verifier test ks",
      role: "verifier",
      active: true
    )

    hypothesis = Hypothesis.create!(
      domain: "netops",
      attack_type: "credential_access",
      description: "Brute force attempts on multiple user accounts",
      confidence: 0.8,
      status: "critiqued",
      metadata: {}
    )

    payload = [
      {
        type: "formal_check",
        tool: "Change management system",
        query: "Check maintenance window",
        expected_if_true: "Matches change window",
        expected_if_false: "No matching change"
      },
      {
        type: "tool_query",
        tool: "Syslog cross-correlation",
        query: "Cross-check auth logs",
        expected_if_true: "Correlated failures",
        expected_if_false: "No correlated failures"
      },
      {
        type: "external_lookup",
        tool: "Threat intel",
        query: "IP reputation lookup",
        expected_if_true: "Known bad infrastructure",
        expected_if_false: "No known intel"
      }
    ]

    VerifierJobTestDouble.test_payload = payload

    Kernel.module_eval do
      alias_method :__orig_rand_for_verifier_test, :rand
      define_method(:rand) { |_max = nil| 0.0 }
    end

    begin
      VerifierJobTestDouble.new.perform(hypothesis.id)
    ensure
      Kernel.module_eval do
        alias_method :rand, :__orig_rand_for_verifier_test
        remove_method :__orig_rand_for_verifier_test
      end
    end

    hypothesis.reload

    assert_equal "corroborated", hypothesis.status
    assert_equal 1, hypothesis.verifications.count
    assert hypothesis.confidence <= 0.9
  end
end
