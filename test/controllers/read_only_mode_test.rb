# frozen_string_literal: true

require "test_helper"

class ReadOnlyModeTest < ActionDispatch::IntegrationTest
  setup do
    @previous_read_only = Rails.configuration.x.blackboard_read_only
    @previous_admins = Rails.configuration.x.blackboard_admin_users
    Rails.configuration.x.blackboard_read_only = true
    Rails.configuration.x.blackboard_admin_users = ["admin"]
  end

  teardown do
    Rails.configuration.x.blackboard_read_only = @previous_read_only
    Rails.configuration.x.blackboard_admin_users = @previous_admins
  end

  test "guest user is blocked from mutating request with flash message" do
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

    assert_no_difference("HistoricalKnowledgeEntry.count") do
      post add_historical_knowledge_alert_path(alert),
           params: {
             historical_knowledge: {
               knowledge_type: "operator_playbook",
               match_signature: "credential abuse",
               operator_severity: "medium",
               operator_name: "guest-user",
               notes: "guest should not be able to save"
             }
           },
           headers: { "X-Remote-User" => "guest" }
    end

    assert_redirected_to dashboard_path
    assert_equal "Read-only mode is enabled. This action requires admin access.", flash[:alert]
    assert_equal true, flash[:read_only_blocked]
  end

  test "admin user can perform mutating request in read-only mode" do
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
      post add_historical_knowledge_alert_path(alert),
           params: {
             historical_knowledge: {
               knowledge_type: "operator_playbook",
               match_signature: "credential abuse",
               operator_severity: "medium",
               operator_name: "admin-user",
               notes: "admin can save"
             }
           },
           headers: { "X-Remote-User" => "admin" }
    end

    assert_redirected_to alert_path(alert)
    assert_equal "Historical Database entry saved. Future matching alerts will use operator severity.", flash[:notice]
  end
end
