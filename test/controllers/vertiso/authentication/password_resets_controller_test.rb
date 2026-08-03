# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

unless defined?(RedisClient::Error)
  # Optional host transport error used to verify production dispatch handling.
  module RedisClient
    class Error < StandardError
    end
  end
end

# Exercises production-compatible password recovery through engine routes.
class VertisoAuthenticationPasswordResetsControllerTest < ActionDispatch::IntegrationTest
  FORGOT_PASSWORD_PATH = "/authentication/forgot-password"
  LOGIN_PATH = "/authentication/login"
  PASSWORD = "TestPassword1234!"
  NEW_PASSWORD = "BrandNewPass1234!"

  module LockRecorder
    # Runs the supplied block under the real Active Record lock and records it.
    #
    # @return [Object]
    def with_lock(...)
      Thread.current[:vertiso_authentication_lock_count] =
        Thread.current[:vertiso_authentication_lock_count].to_i + 1
      previous_lock_state = Thread.current[:vertiso_authentication_inside_lock]
      Thread.current[:vertiso_authentication_inside_lock] = true

      super do
        hook = Thread.current[:vertiso_authentication_lock_hook]
        Thread.current[:vertiso_authentication_lock_hook] = nil
        hook&.call(self)
        yield
      end
    ensure
      Thread.current[:vertiso_authentication_inside_lock] = previous_lock_state
    end
  end

  module TokenLookupRecorder
    # Records whether real password-reset token lookups occur under the lock.
    #
    # @param purpose [Symbol]
    # @param token [String]
    # @return [ApplicationRecord, nil]
    def find_by_token_for(purpose, token)
      if purpose == :password_reset
        Thread.current[:vertiso_authentication_reset_lookups] ||= []
        Thread.current[:vertiso_authentication_reset_lookups] <<
          Thread.current[:vertiso_authentication_inside_lock]
      end

      super
    end
  end

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

  User.prepend(LockRecorder) unless User < LockRecorder
  User.singleton_class.prepend(TokenLookupRecorder) unless User.singleton_class < TokenLookupRecorder

  setup do
    Rails.cache.clear
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.deliveries.clear
    reset_lock_instrumentation
    configure_host
    @principal = create_principal
    @principal.update!(email_confirmation_attribute => Time.current)
  end

  teardown do
    Rails.cache.clear
    clear_enqueued_jobs
    clear_performed_jobs
    reset_lock_instrumentation
    Vertiso::Authentication.reset_configuration!
  end

  test "the reset request form prepopulates email from the query string" do
    get FORGOT_PASSWORD_PATH, params: { email: "person@example.com" }

    assert_response :ok
    assert_includes response.body, 'value="person@example.com"'
  end

  test "an authenticated reset request form redirects to root with the production notice" do
    log_in

    get FORGOT_PASSWORD_PATH

    assert_redirected_to "/"
    assert_equal I18n.t("vertiso.authentication.password_resets.already_signed_in"),
                 flash[:notice]
  end

  test "existing and missing emails receive identical public responses" do
    existing_response = post_reset_request(" PERSON@EXAMPLE.COM ")
    existing_jobs = enqueued_jobs.size
    clear_enqueued_jobs

    missing_response = post_reset_request("missing@example.com")

    assert_equal existing_response, missing_response
    assert_equal 1, existing_jobs
    assert_empty enqueued_jobs
  end

  test "an unconfirmed email receives the same neutral response without dispatch" do
    @principal.update!(email_confirmation_attribute => nil)

    response_contract = post_reset_request(@principal.email)

    assert_equal neutral_reset_response, response_contract
    assert_empty enqueued_jobs
  end

  test "an enqueue failure preserves the same neutral response" do
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter =
      EnqueueFailureAdapter.new(RedisClient::Error)

    response_contract = post_reset_request(@principal.email)

    assert_equal neutral_reset_response, response_contract
  ensure
    ActiveJob::Base.queue_adapter = original_adapter if original_adapter
  end

  test "the controller mints the reset token before the asynchronous mailer runs" do
    post FORGOT_PASSWORD_PATH, params: { email: @principal.email }
    @principal.update!(
      password: "IntermediatePass1234!",
      password_confirmation: "IntermediatePass1234!"
    )

    perform_enqueued_jobs

    token = reset_token_from(ActionMailer::Base.deliveries.last)
    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test "the eleventh reset request in one hour returns the branded rate-limit branch" do
    10.times do
      post FORGOT_PASSWORD_PATH, params: { email: "missing@example.com" }
      assert_redirected_to LOGIN_PATH
    end

    post FORGOT_PASSWORD_PATH, params: { email: "missing@example.com" }

    assert_response :see_other
    assert_redirected_to FORGOT_PASSWORD_PATH
    assert_equal I18n.t("vertiso.authentication.password_resets.rate_limited"),
                 flash[:alert]
  end

  test "a malformed token cannot mutate a signed-in visitor session on GET" do
    log_in
    original_cookie = cookies[:remember_token]

    get reset_token_path("malformed")

    assert_redirected_to LOGIN_PATH
    assert_equal original_cookie, cookies[:remember_token]
    assert_equal I18n.t("vertiso.authentication.password_resets.invalid_link"),
                 flash[:alert]
  end

  test "an expired token redirects to login" do
    token = @principal.generate_token_for(:password_reset)

    travel 61.minutes do
      get reset_token_path(token)
    end

    assert_redirected_to LOGIN_PATH
    assert_equal I18n.t("vertiso.authentication.password_resets.invalid_link"),
                 flash[:alert]
  end

  test "changing email invalidates an outstanding reset token" do
    token = @principal.generate_token_for(:password_reset)
    @principal.update!(email: "changed@example.com")

    get reset_token_path(token)

    assert_redirected_to LOGIN_PATH
    assert_equal I18n.t("vertiso.authentication.password_resets.invalid_link"),
                 flash[:alert]
  end

  test "a valid token logs out a signed-in visitor only after validation and renders the form" do
    token = @principal.generate_token_for(:password_reset)
    log_in

    get reset_token_path(token)

    assert_response :ok
    assert_predicate cookies[:remember_token], :blank?
    assert_includes response.body,
                    I18n.t("vertiso.authentication.password_resets.edit.title")
  end

  test "blank password renders unprocessable content without changing the password" do
    token = @principal.generate_token_for(:password_reset)

    patch_reset(token, password: "", confirmation: "")

    assert_response :unprocessable_content
    assert @principal.reload.authenticate(PASSWORD)
  end

  test "mismatched password confirmation renders unprocessable content" do
    token = @principal.generate_token_for(:password_reset)

    patch_reset(
      token,
      password: NEW_PASSWORD,
      confirmation: "DifferentPass1234!"
    )

    assert_response :unprocessable_content
    assert @principal.reload.authenticate(PASSWORD)
  end

  test "a malformed update token redirects without changing the password" do
    patch_reset(
      "malformed",
      password: NEW_PASSWORD,
      confirmation: NEW_PASSWORD
    )

    assert_redirected_to LOGIN_PATH
    assert @principal.reload.authenticate(PASSWORD)
    assert_equal I18n.t("vertiso.authentication.password_resets.invalid_link"),
                 flash[:alert]
  end

  test "update uses the real lock and revalidates the token immediately inside it" do
    token = @principal.generate_token_for(:password_reset)

    patch_reset(
      token,
      password: NEW_PASSWORD,
      confirmation: NEW_PASSWORD
    )

    assert_equal 1, Thread.current[:vertiso_authentication_lock_count]
    assert_equal [false, true],
                 Thread.current[:vertiso_authentication_reset_lookups]
  end

  test "an invalidation after the first lookup is caught by locked revalidation" do
    token = @principal.generate_token_for(:password_reset)
    Thread.current[:vertiso_authentication_lock_hook] = lambda do |principal|
      principal.update!(
        password: "ConcurrentPass1234!",
        password_confirmation: "ConcurrentPass1234!"
      )
    end

    patch_reset(
      token,
      password: NEW_PASSWORD,
      confirmation: NEW_PASSWORD
    )

    assert_redirected_to LOGIN_PATH
    assert @principal.reload.authenticate("ConcurrentPass1234!")
    assert_not @principal.authenticate(NEW_PASSWORD)
    assert_equal [false, true],
                 Thread.current[:vertiso_authentication_reset_lookups]
  end

  test "successful reset changes password invalidates old tokens and establishes the new login" do
    reset_token = @principal.generate_token_for(:password_reset)
    old_browser_token = @principal.generate_token_for(:remember_token)

    patch_reset(
      reset_token,
      password: NEW_PASSWORD,
      confirmation: NEW_PASSWORD
    )

    assert_redirected_to "/signed-in?principal_id=#{@principal.id}"
    assert_equal I18n.t("vertiso.authentication.password_resets.password_changed"),
                 flash[:notice]
    assert @principal.reload.authenticate(NEW_PASSWORD)
    assert_not @principal.authenticate(PASSWORD)
    assert_nil User.find_by_token_for(:password_reset, reset_token)
    assert_nil User.find_by_token_for(:remember_token, old_browser_token)

    get "/authentication-state"

    state = response.parsed_body
    assert_equal @principal.id, state.fetch("principal_id")
    assert_equal @principal,
                 User.find_by_token_for(
                   :remember_token,
                   state.fetch("remember_token")
                 )
    assert Vertiso::Authentication::AuthenticationSession.exists?(
      principal: @principal
    )
  end

  test "successful reset replaces a different current login with the token principal" do
    other = create_principal(
      email: "other@example.com",
      user_name: "other"
    )
    other.update!(email_confirmation_attribute => Time.current)
    token = @principal.generate_token_for(:password_reset)
    log_in(other)

    patch_reset(
      token,
      password: NEW_PASSWORD,
      confirmation: NEW_PASSWORD
    )
    get "/authentication-state"

    assert_equal @principal.id, response.parsed_body.fetch("principal_id")
  end

  private

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
      config.post_authentication_destination = lambda do |controller, principal|
        controller.main_app.signed_in_path(principal_id: principal.id)
      end
      config.mailer_sender = -> { "authentication@example.test" }
      config.mailer_host = -> { "auth.example.test" }
      config.mailer_url_options = -> { { protocol: "https" } }
    end
  end

  def create_principal(email: "person@example.com", user_name: "person")
    User.create!(
      email:,
      Vertiso::Authentication.configuration.user_name_attribute => user_name,
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
  end

  def log_in(principal = @principal)
    post LOGIN_PATH, params: {
      session: {
        login: principal.email,
        password: PASSWORD
      }
    }
  end

  def post_reset_request(email)
    post FORGOT_PASSWORD_PATH, params: { email: }
    [response.status, response.location, flash[:notice], flash[:alert]]
  end

  def neutral_reset_response
    [
      302,
      "http://www.example.com#{LOGIN_PATH}",
      I18n.t("vertiso.authentication.password_resets.email_sent"),
      nil
    ]
  end

  def reset_token_path(token)
    "/authentication/reset-password/#{token}"
  end

  def patch_reset(token, password:, confirmation:)
    patch reset_token_path(token), params: {
      user: {
        password:,
        password_confirmation: confirmation
      }
    }
  end

  def reset_token_from(mail)
    mail.html_part.body.decoded[%r{/reset-password/([^"<\s]+)}, 1]
  end

  def email_confirmation_attribute
    Vertiso::Authentication.configuration.email_confirmed_at_attribute
  end

  def reset_lock_instrumentation
    Thread.current[:vertiso_authentication_lock_count] = 0
    Thread.current[:vertiso_authentication_inside_lock] = false
    Thread.current[:vertiso_authentication_lock_hook] = nil
    Thread.current[:vertiso_authentication_reset_lookups] = []
  end

  def mapped_host?
    ENV.fetch("DUMMY_APP", "dummy_standard") == "dummy_mapped"
  end
end
