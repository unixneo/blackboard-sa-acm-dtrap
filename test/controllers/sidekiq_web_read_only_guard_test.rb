# frozen_string_literal: true

require "test_helper"

class SidekiqWebReadOnlyGuardTest < ActionDispatch::IntegrationTest
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

  test "guest mutating request to /sidekiq is blocked by middleware" do
    post "/sidekiq/queues/default", headers: { "X-Remote-User" => "guest" }, params: { action: "clear" }

    assert_response :forbidden
    assert_includes response.body, "Forbidden: read-only mode"
  end

  test "admin mutating request to /sidekiq is allowed through middleware" do
    post "/sidekiq/queues/default", headers: { "X-Remote-User" => "admin" }, params: { action: "clear" }

    assert_not_equal 403, response.status
  end

  test "guest safe request to /sidekiq is allowed through middleware" do
    get "/sidekiq", headers: { "X-Remote-User" => "guest" }

    assert_not_equal 403, response.status
  end
end
