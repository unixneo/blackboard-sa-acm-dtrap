# frozen_string_literal: true

require "test_helper"

class HistoricalDataJobTest < ActiveJob::TestCase
  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "caps confidence based on matched historical entry, stamps metadata, and enqueues alert job" do
    ks = KnowledgeSource.create!(
      name: "historical_data test ks",
      role: "historical_data",
      active: true
    )

    hypothesis = Hypothesis.create!(
      domain: "cybersecurity",
      attack_type: "credential_access",
      description: "Credential stuffing against login endpoint",
      confidence: 0.97,
      status: "corroborated",
      metadata: {}
    )

    entry = HistoricalKnowledgeEntry.create!(
      domain: "cybersecurity",
      knowledge_type: "operator_playbook",
      match_attack_type: "credential_access",
      operator_severity: "medium",
      operator_name: "oncall-a",
      notes: "Known noisy source"
    )

    assert_enqueued_with(job: AlertJob, args: [hypothesis.id]) do
      HistoricalDataJob.perform_now(hypothesis.id)
    end

    hypothesis.reload
    gate = hypothesis.metadata["historical_data_gate"]
    history = hypothesis.metadata["confidence_history"]

    assert_in_delta 0.89, hypothesis.confidence, 0.0001
    assert_equal true, gate["matched"]
    assert_equal entry.id, gate["historical_knowledge_entry_id"]
    assert_equal "oncall-a", gate["operator_name"]
    assert_equal "medium", gate["operator_severity"]
    assert_equal ks.id, gate["knowledge_source_id"]
    assert_equal 1, history.size
    assert_match(/HistoricalDataKS cap via ##{entry.id}/, history.first["reason"])
  end

  test "stamps unmatched metadata and still enqueues alert job when no historical match exists" do
    KnowledgeSource.create!(
      name: "historical_data no-match ks",
      role: "historical_data",
      active: true
    )

    hypothesis = Hypothesis.create!(
      domain: "cybersecurity",
      attack_type: "exfiltration",
      description: "Large outbound transfer to new destination",
      confidence: 0.91,
      status: "corroborated",
      metadata: {}
    )

    assert_enqueued_with(job: AlertJob, args: [hypothesis.id]) do
      HistoricalDataJob.perform_now(hypothesis.id)
    end

    hypothesis.reload
    gate = hypothesis.metadata["historical_data_gate"]

    assert_equal false, gate["matched"]
    assert_nil gate["historical_knowledge_entry_id"]
    assert_nil gate["operator_name"]
    assert_nil gate["operator_severity"]
    assert_in_delta 0.91, hypothesis.confidence, 0.0001
  end

  test "does not enqueue alert job when hypothesis is not corroborated" do
    hypothesis = Hypothesis.create!(
      domain: "cybersecurity",
      attack_type: "reconnaissance",
      description: "Port scan from single source",
      confidence: 0.7,
      status: "critiqued"
    )

    assert_no_enqueued_jobs do
      HistoricalDataJob.perform_now(hypothesis.id)
    end
  end
end
