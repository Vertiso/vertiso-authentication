# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

unless defined?(RedisClient::Error)
  # Optional host transport error used to verify production dispatch handling.
  module RedisClient
    class Error < StandardError
    end
  end
end

# Exercises production-compatible email confirmation through engine routes.
class VertisoAuthenticationConfirmationsControllerTest < ActionDispatch::IntegrationTest
  CONFIRMATION_PATH = "/authentication/confirm-email"
  LOGIN_PATH = "/authentication/login"
  PASSWORD = "TestPassword1234!"

  setup do
    Rails.cache.clear
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.deliveries.clear
    configure_host
    @principal = create_principal
  end

  teardown do
    Rails.cache.clear
    clear_enqueued_jobs
    clear_performed_jobs
    Vertiso::Authentication.reset_configuration!
  end

  test "a valid anonymous token confirms the configured timestamp and redirects to login" do
    token = @principal.generate_token_for(:email_verification)

    freeze_time do
      get confirmation_token_path(token)

      assert_redirected_to LOGIN_PATH
      assert_equal Time.current,
                   @principal.reload.public_send(email_confirmation_attribute)
      assert_equal I18n.t("vertiso.authentication.confirmations.confirmed"),
                   flash[:notice]
    end
  end

  test "an expired token redirects anonymously with the invalid-link alert" do
    token = @principal.generate_token_for(:email_verification)

    travel 25.hours do
      get confirmation_token_path(token)
    end

    assert_redirected_to LOGIN_PATH
    assert_nil @principal.reload.public_send(email_confirmation_attribute)
    assert_equal I18n.t("vertiso.authentication.confirmations.invalid_link"),
                 flash[:alert]
  end

  test "changing the configured email invalidates an outstanding token" do
    token = @principal.generate_token_for(:email_verification)
    @principal.update!(email: "changed@example.com")

    get confirmation_token_path(token)

    assert_redirected_to LOGIN_PATH
    assert_nil @principal.reload.public_send(email_confirmation_attribute)
    assert_equal I18n.t("vertiso.authentication.confirmations.invalid_link"),
                 flash[:alert]
  end

  test "a malformed token redirects anonymously with the invalid-link alert" do
    get confirmation_token_path("malformed")

    assert_redirected_to LOGIN_PATH
    assert_nil @principal.reload.public_send(email_confirmation_attribute)
    assert_equal I18n.t("vertiso.authentication.confirmations.invalid_link"),
                 flash[:alert]
  end

  test "an already-confirmed token preserves the original timestamp" do
    token = @principal.generate_token_for(:email_verification)
    original_timestamp = 1.hour.ago.change(usec: 0)
    @principal.update!(email_confirmation_attribute => original_timestamp)

    get confirmation_token_path(token)

    assert_redirected_to LOGIN_PATH
    assert_equal original_timestamp,
                 @principal.reload.public_send(email_confirmation_attribute)
    assert_equal I18n.t("vertiso.authentication.confirmations.already_confirmed"),
                 flash[:notice]
  end

  test "a signed-in principal confirms to the configured host destination" do
    token = @principal.generate_token_for(:email_verification)
    log_in

    get confirmation_token_path(token)

    assert_redirected_to "/confirmed?principal_id=#{@principal.id}"
    assert_predicate @principal.reload, :email_verified?
  end

  test "resend enqueues a confirmation message for the signed-in principal" do
    log_in

    assert_enqueued_emails 1 do
      post CONFIRMATION_PATH
    end

    assert_redirected_to "/confirmation-required"
    assert_equal I18n.t("vertiso.authentication.confirmations.resent"),
                 flash[:notice]
  end

  test "resend skips an already-confirmed signed-in principal" do
    @principal.update!(email_confirmation_attribute => Time.current)
    log_in

    assert_no_enqueued_emails do
      post CONFIRMATION_PATH
    end

    assert_redirected_to "/"
    assert_equal I18n.t("vertiso.authentication.confirmations.already_confirmed"),
                 flash[:notice]
  end

  test "an anonymous resend redirects to login before evaluating its principal rate-limit key" do
    post CONFIRMATION_PATH

    assert_response :see_other
    assert_redirected_to LOGIN_PATH
    assert_no_enqueued_emails
  end

  test "the eleventh resend in one hour returns the configured recovery destination and alert" do
    log_in

    10.times do
      post CONFIRMATION_PATH
      assert_redirected_to "/confirmation-required"
    end

    post CONFIRMATION_PATH

    assert_response :see_other
    assert_redirected_to "/confirmation-required"
    assert_equal I18n.t("vertiso.authentication.confirmations.rate_limited"),
                 flash[:alert]
  end

  test "a confirmation enqueue failure returns the production dispatch-failed branch" do
    log_in
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = EnqueueFailureAdapter.new

    post CONFIRMATION_PATH

    assert_redirected_to "/confirmation-required"
    assert_equal I18n.t("vertiso.authentication.confirmations.dispatch_failed"),
                 flash[:alert]
    assert_not_equal I18n.t("vertiso.authentication.confirmations.resent"),
                     flash[:notice]
  ensure
    ActiveJob::Base.queue_adapter = original_adapter if original_adapter
  end

  test "an optional Redis transport failure returns the production dispatch-failed branch" do
    log_in
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter =
      EnqueueFailureAdapter.new(RedisClient::Error)

    post CONFIRMATION_PATH

    assert_redirected_to "/confirmation-required"
    assert_equal I18n.t("vertiso.authentication.confirmations.dispatch_failed"),
                 flash[:alert]
  ensure
    ActiveJob::Base.queue_adapter = original_adapter if original_adapter
  end

  private

  # Queue adapter that exercises the real mailer job's enqueue failure path.
  class EnqueueFailureAdapter
    # @param error_class [Class]
    def initialize(error_class = ActiveJob::EnqueueError)
      @error_class = error_class
    end

    # @param _job [ActiveJob::Base]
    # @return [void]
    def enqueue(_job)
      raise @error_class, "queue unavailable"
    end

    # @param _job [ActiveJob::Base]
    # @param _timestamp [Numeric]
    # @return [void]
    def enqueue_at(_job, _timestamp)
      raise @error_class, "queue unavailable"
    end
  end

  def configure_host
    Vertiso::Authentication.reset_configuration!
    Vertiso::Authentication.configure do |config|
      if mapped_host?
        config.user_name_attribute = :handle
        config.email_confirmed_at_attribute = :email_confirmed_at
      end
      config.confirmation_required_destination = lambda do |controller, _principal|
        controller.main_app.confirmation_required_path
      end
      config.post_confirmation_destination = lambda do |controller, principal|
        controller.main_app.confirmed_path(principal_id: principal.id)
      end
      config.post_authentication_destination = lambda do |controller, principal|
        controller.main_app.signed_in_path(principal_id: principal.id)
      end
      config.mailer_sender = "authentication@example.test"
      config.mailer_host = "auth.example.test"
      config.mailer_url_options = { protocol: "https" }
    end
  end

  def create_principal
    User.create!(
      email: "person@example.com",
      Vertiso::Authentication.configuration.user_name_attribute => "person",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
  end

  def log_in
    post LOGIN_PATH, params: {
      session: {
        login: @principal.email,
        password: PASSWORD
      }
    }
  end

  def confirmation_token_path(token)
    "#{CONFIRMATION_PATH}/#{token}"
  end

  def email_confirmation_attribute
    Vertiso::Authentication.configuration.email_confirmed_at_attribute
  end

  def mapped_host?
    ENV.fetch("DUMMY_APP", "dummy_standard") == "dummy_mapped"
  end
end
