# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationAuthenticationSessionTest < ActiveSupport::TestCase
  AuthenticationSession = Vertiso::Authentication::AuthenticationSession

  setup do
    configure_mapped_host if mapped_host?
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "derives deterministic active and inactive states from expiry boundaries" do
    reference_time = Time.zone.local(2026, 8, 2, 12, 0, 0)
    no_expiry = create_session(session_identifier: "no-expiry", expires_at: nil)
    after_boundary = create_session(
      session_identifier: "after-boundary",
      expires_at: reference_time + 1.second
    )
    at_boundary = create_session(
      session_identifier: "at-boundary",
      expires_at: reference_time
    )
    before_boundary = create_session(
      session_identifier: "before-boundary",
      expires_at: reference_time - 1.second
    )

    assert no_expiry.active_at?(reference_time)
    assert after_boundary.active_at?(reference_time)
    assert_not at_boundary.active_at?(reference_time)
    assert_not before_boundary.active_at?(reference_time)
    assert_equal [no_expiry, after_boundary],
                 AuthenticationSession.active_at(reference_time).order(:id).to_a
    assert_equal [at_boundary, before_boundary],
                 AuthenticationSession.inactive_at(reference_time).order(:id).to_a
  end

  test "derives current active and inactive scopes from the current time" do
    travel_to Time.zone.local(2026, 8, 2, 12, 0, 0) do
      active = create_session(
        session_identifier: "active",
        expires_at: 1.hour.from_now
      )
      inactive = create_session(
        session_identifier: "inactive",
        expires_at: 1.second.ago
      )

      assert_predicate active, :active?
      assert_not_predicate inactive, :active?
      assert_equal [active], AuthenticationSession.active.to_a
      assert_equal [inactive], AuthenticationSession.inactive.to_a
    end
  end

  test "requires a unique session identifier" do
    create_session(session_identifier: "duplicate")

    assert_raises(ActiveRecord::RecordNotUnique) do
      create_session(session_identifier: "duplicate")
    end
  end

  test "permits sessions without a principal" do
    session = create_session(session_identifier: "anonymous", principal: nil)

    assert_nil session.principal
  end

  test "persists portable hash data with an empty default" do
    blank_session = AuthenticationSession.create!(session_identifier: "blank-data")
    session = AuthenticationSession.create!(
      session_identifier: "hash-data",
      data: { "browser" => "Firefox", "versions" => ["1", "2"] }
    )

    assert_equal({}, blank_session.data)
    assert_equal({ "browser" => "Firefox", "versions" => ["1", "2"] }, session.data)
  end

  test "touches the activity timestamp" do
    session = create_session(session_identifier: "activity")
    activity_time = Time.zone.local(2026, 8, 2, 12, 0, 0)

    travel_to activity_time do
      session.touch_activity!
    end

    assert_equal activity_time, session.reload.last_activity_at
  end

  test "belongs to a principal and is reachable through its session association" do
    principal = create_user
    session = create_session(
      principal:,
      session_identifier: "principal-session"
    )

    assert_equal principal, session.principal
    assert_equal [session], principal.authentication_sessions.to_a
  end

  test "does not make the database session metadata a browser token authority" do
    principal = create_user
    token = principal.generate_token_for(:remember_token)
    session = create_session(
      principal:,
      session_identifier: "browser-token-independence",
      expires_at: 1.second.ago
    )

    session.destroy!

    assert_equal principal, User.find_by_token_for(:remember_token, token)
  end

  private

  # @return [Vertiso::Authentication::AuthenticationSession]
  def create_session(session_identifier:, principal: create_user, **attributes)
    AuthenticationSession.create!(
      **attributes,
      principal:,
      session_identifier:
    )
  end

  # @return [User]
  def create_user
    unique_value = SecureRandom.hex(8)
    attributes = {
      email: "session-#{unique_value}@example.com",
      password: "TestPassword1234!",
      password_confirmation: "TestPassword1234!"
    }
    attributes[configured_user_name_attribute] = "session-#{unique_value}"

    User.create!(attributes)
  end

  # @return [Symbol]
  def configured_user_name_attribute
    User.attribute_names.include?("handle") ? :handle : :user_name
  end

  # @return [Boolean]
  def mapped_host?
    User.attribute_names.include?("handle")
  end

  # @return [void]
  def configure_mapped_host
    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end
  end
end
