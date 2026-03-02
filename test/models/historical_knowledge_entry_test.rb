# frozen_string_literal: true

require "test_helper"

class HistoricalKnowledgeEntryTest < ActiveSupport::TestCase
  test "notes required for non common_public_scan knowledge types" do
    entry = HistoricalKnowledgeEntry.new(
      domain: "cybersecurity",
      knowledge_type: "operator_playbook",
      operator_severity: "medium",
      operator_name: "alice",
      notes: ""
    )

    assert_not entry.valid?
    assert_includes entry.errors[:notes], "can't be blank"
  end

  test "notes optional for common_public_scan" do
    entry = HistoricalKnowledgeEntry.new(
      domain: "cybersecurity",
      knowledge_type: "common_public_scan",
      operator_severity: "low",
      operator_name: "alice",
      notes: ""
    )

    assert entry.valid?
  end

  test "match_for_hypothesis prefers exact attack type over signature match" do
    hypothesis = Hypothesis.create!(
      domain: "cybersecurity",
      attack_type: "credential_access",
      description: "Password spray attempts against VPN concentrator",
      confidence: 0.9,
      status: "corroborated"
    )

    signature_only = HistoricalKnowledgeEntry.create!(
      domain: "cybersecurity",
      knowledge_type: "operator_playbook",
      match_signature: "password spray",
      operator_severity: "low",
      operator_name: "sig-operator",
      notes: "signature rule"
    )

    exact_attack = HistoricalKnowledgeEntry.create!(
      domain: "cybersecurity",
      knowledge_type: "operator_playbook",
      match_attack_type: "credential_access",
      operator_severity: "medium",
      operator_name: "attack-operator",
      notes: "exact attack rule"
    )

    result = HistoricalKnowledgeEntry.match_for_hypothesis(hypothesis, summary: hypothesis.description)

    assert_equal exact_attack.id, result.id
    assert_not_equal signature_only.id, result.id
  end

  test "match_for_hypothesis respects active and domain scoping" do
    hypothesis = Hypothesis.create!(
      domain: "netops",
      attack_type: "denial_of_service",
      description: "Sustained high-rate SYN flood on edge service",
      confidence: 0.88,
      status: "corroborated"
    )

    HistoricalKnowledgeEntry.create!(
      domain: "cybersecurity",
      knowledge_type: "operator_playbook",
      match_attack_type: "denial_of_service",
      operator_severity: "low",
      operator_name: "wrong-domain",
      notes: "wrong domain"
    )

    HistoricalKnowledgeEntry.create!(
      domain: "netops",
      knowledge_type: "operator_playbook",
      match_attack_type: "denial_of_service",
      operator_severity: "low",
      operator_name: "inactive",
      notes: "inactive record",
      active: false
    )

    active_match = HistoricalKnowledgeEntry.create!(
      domain: "netops",
      knowledge_type: "operator_playbook",
      match_attack_type: "denial_of_service",
      operator_severity: "high",
      operator_name: "active-netops",
      notes: "active record"
    )

    result = HistoricalKnowledgeEntry.match_for_hypothesis(hypothesis, summary: hypothesis.description)

    assert_equal active_match.id, result.id
  end
end
