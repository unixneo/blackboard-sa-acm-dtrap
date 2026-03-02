# frozen_string_literal: true

require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  test "add_historical_knowledge creates entry and redirects with notice" do
    hypothesis = Hypothesis.create!(
      domain: "cybersecurity",
      attack_type: "credential_access",
      description: "Repeated login failures and lockouts",
      confidence: 0.9,
      status: "corroborated"
    )
    alert = Alert.create!(
      hypothesis: hypothesis,
      domain: "cybersecurity",
      severity: "high",
      summary: "Credential abuse signal"
    )

    assert_difference("HistoricalKnowledgeEntry.count", 1) do
      post add_historical_knowledge_alert_path(alert), params: {
        historical_knowledge: {
          knowledge_type: "operator_playbook",
          match_signature: "credential abuse",
          operator_severity: "medium",
          operator_name: "analyst-1",
          notes: "Use medium unless verified compromise"
        }
      }
    end

    created = HistoricalKnowledgeEntry.order(:id).last
    assert_redirected_to alert_path(alert)
    assert_equal "Historical Database entry saved. Future matching alerts will use operator severity.", flash[:notice]
    assert_equal alert.id, created.alert_id
    assert_equal hypothesis.id, created.hypothesis_id
    assert_equal "cybersecurity", created.domain
    assert_equal "credential_access", created.match_attack_type
  end

  test "add_historical_knowledge rejects invalid payload and redirects with validation error" do
    hypothesis = Hypothesis.create!(
      domain: "cybersecurity",
      attack_type: "denial_of_service",
      description: "Sustained high-rate request burst",
      confidence: 0.92,
      status: "corroborated"
    )
    alert = Alert.create!(
      hypothesis: hypothesis,
      domain: "cybersecurity",
      severity: "critical",
      summary: "Potential service disruption"
    )

    assert_no_difference("HistoricalKnowledgeEntry.count") do
      post add_historical_knowledge_alert_path(alert), params: {
        historical_knowledge: {
          knowledge_type: "operator_playbook",
          match_signature: "burst",
          operator_severity: "low",
          operator_name: "analyst-2",
          notes: ""
        }
      }
    end

    assert_redirected_to alert_path(alert)
    assert_match(/Notes can't be blank/i, flash[:alert])
  end
end
