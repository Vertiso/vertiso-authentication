# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "omniauth"

class VertisoAuthenticationOauthSessionsControllerTest < ActionDispatch::IntegrationTest
  CALLBACK_PATH = "/authentication/auth/google_oauth2/callback"
  COMPLETE_EMAIL_PATH = "/authentication/auth/email"
  LOGIN_PATH = "/authentication/login"
  PROMPT_EMAIL_PATH = "/authentication/auth/email"
  STATE_PATH = "/authentication-state"
  PASSWORD = "TestPassword1234!"

  setup do
    ActiveJob::Base.queue_adapter = :test
    configure_host
    @provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Vertiso::Authentication.reset_configuration!
  end

  test "rejects a missing or inactive provider" do
    missing_auth = oauth_auth(provider: "missing", uid: "missing-uid")

    get CALLBACK_PATH, env: { "omniauth.auth" => missing_auth }

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t("vertiso.authentication.sessions.oauth_unavailable"),
      request.flash[:alert]
    )

    @provider.update!(active: false)

    get CALLBACK_PATH, env: { "omniauth.auth" => oauth_auth(uid: "inactive-uid") }

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t("vertiso.authentication.sessions.oauth_unavailable"),
      request.flash[:alert]
    )
  end

  test "provider failure redirects to login with the callback message" do
    get "/authentication/auth/failure",
        params: {
          message: "access_denied"
        }

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_failure",
        message: "access_denied"
      ),
      request.flash[:alert]
    )
  end

  test "developer callback is rejected outside development without mutations" do
    developer = Vertiso::Authentication::OauthProvider.create!(
      name: "developer",
      display_name: "Developer",
      trusts_email: true
    )
    owner = create_principal(
      email: "developer@example.com",
      user_name: "developer"
    )
    account = owner.authentication_oauth_accounts.create!(
      oauth_provider: developer,
      provider_uid: "developer-#{owner.id}",
      email: "original@example.com",
      name: "Original Developer",
      user_info: {
        "source" => "original"
      },
      user_credentials: {
        "token" => "original-token"
      }
    )
    auth = oauth_auth(
      provider: "developer",
      uid: "developer-#{owner.id}",
      email: owner.email,
      name: "Mutated Developer",
      token: "mutated-token"
    )

    with_rails_environment("production") do
      assert_no_difference(
        [
          -> { User.count },
          -> { Vertiso::Authentication::UserOauthAccount.count },
          -> { Vertiso::Authentication::AuthenticationSession.count }
        ]
      ) do
        get "/authentication/auth/developer/callback",
            env: { "omniauth.auth" => auth }
      end
    end

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t("vertiso.authentication.sessions.oauth_unavailable"),
      request.flash[:alert]
    )
    assert_nil current_principal_id
    assert_equal "original@example.com", account.reload.email
    assert_equal "Original Developer", account.name
    assert_equal({ "source" => "original" }, account.user_info)
    assert_equal({ "token" => "original-token" }, account.user_credentials)
    assert_nil account.last_used_at
  end

  test "existing identity signs in its owner and replaces callback metadata" do
    owner = create_principal(
      email: "owner@example.com",
      user_name: "owner"
    )
    account = owner.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "existing-uid",
      email: "old@example.com",
      name: "Old Name",
      user_info: { "old" => "profile" },
      user_credentials: {
        "token" => "old-token",
        "refresh_token" => "old-refresh-token"
      }
    )
    auth = oauth_auth(
      uid: "existing-uid",
      email: "new@example.com",
      name: "New Name",
      token: "new-token",
      refresh_token: nil
    )

    freeze_time do
      get CALLBACK_PATH, env: { "omniauth.auth" => auth }

      assert_redirected_to oauth_destination(owner)
      assert_equal owner.id, current_principal_id
      assert_equal Time.current, account.reload.last_used_at
      assert_equal "new@example.com", account.email
      assert_equal "New Name", account.name
      assert_equal auth.info.to_hash, account.user_info
      assert_equal auth.credentials.to_hash, account.user_credentials
      assert_nil account.user_credentials["refresh_token"]
    end
  end

  test "signed-in owner gets already-linked response without changing principals" do
    owner = create_principal(
      email: "owner@example.com",
      user_name: "owner"
    )
    account = owner.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "same-owner-uid"
    )
    sign_in(owner)

    get CALLBACK_PATH,
        env: {
          "omniauth.auth" => oauth_auth(
            uid: "same-owner-uid",
            email: owner.email,
            name: "Updated Owner"
          )
        }

    assert_redirected_to oauth_destination(owner)
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_already_linked",
        provider: "Google"
      ),
      request.flash[:notice]
    )
    assert_equal owner.id, current_principal_id
    assert_equal "Updated Owner", account.reload.name
  end

  test "signed-in principal cannot switch to another identity owner" do
    signed_in_principal = create_principal(
      email: "signed-in@example.com",
      user_name: "signed-in"
    )
    identity_owner = create_principal(
      email: "owner@example.com",
      user_name: "owner"
    )
    account = identity_owner.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "other-owner-uid",
      name: "Original Owner"
    )
    sign_in(signed_in_principal)

    get CALLBACK_PATH,
        env: {
          "omniauth.auth" => oauth_auth(
            uid: "other-owner-uid",
            email: identity_owner.email,
            name: "Attempted Switch"
          )
        }

    assert_redirected_to oauth_destination(signed_in_principal)
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_account_linked_to_other_principal",
        provider: "Google"
      ),
      request.flash[:alert]
    )
    assert_equal signed_in_principal.id, current_principal_id
    assert_equal "Original Owner", account.reload.name
  end

  test "signed-in principal links a new identity without creating a principal" do
    principal = create_principal(
      email: "signed-in@example.com",
      user_name: "signed-in"
    )
    sign_in(principal)
    auth = oauth_auth(
      uid: "new-link-uid",
      email: nil,
      name: "Provider Name"
    )

    assert_no_difference(-> { User.count }) do
      assert_difference(
        -> { Vertiso::Authentication::UserOauthAccount.count },
        1
      ) do
        get CALLBACK_PATH, env: { "omniauth.auth" => auth }
      end
    end

    account = principal.authentication_oauth_accounts.find_by!(
      oauth_provider: @provider,
      provider_uid: "new-link-uid"
    )

    assert_redirected_to oauth_destination(principal)
    assert_equal principal.id, current_principal_id
    assert_equal auth.info.to_hash, account.user_info
    assert_equal auth.credentials.to_hash, account.user_credentials
    assert_nil account.email
  end

  test "trusted email collision links and signs in the existing principal" do
    existing = create_principal(
      email: "existing@example.com",
      user_name: "existing"
    )
    auth = oauth_auth(
      uid: "trusted-collision",
      email: " Existing@Example.com "
    )

    assert_no_difference(-> { User.count }) do
      assert_difference(
        -> { Vertiso::Authentication::UserOauthAccount.count },
        1
      ) do
        get CALLBACK_PATH, env: { "omniauth.auth" => auth }
      end
    end

    assert_redirected_to oauth_destination(existing)
    assert_equal existing.id, current_principal_id
    assert_equal(
      existing,
      Vertiso::Authentication::UserOauthAccount.find_by!(
        oauth_provider: @provider,
        provider_uid: "trusted-collision"
      ).principal
    )
  end

  test "trusted linked-email collision links and signs in the linked principal" do
    existing = create_principal(
      email: "canonical@example.com",
      user_name: "existing"
    )
    existing.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "existing-linked-email",
      email: "linked@example.com"
    )
    auth = oauth_auth(
      uid: "trusted-linked-collision",
      email: " Linked@Example.com "
    )

    assert_no_difference(-> { User.count }) do
      assert_difference(
        -> { Vertiso::Authentication::UserOauthAccount.count },
        1
      ) do
        get CALLBACK_PATH, env: { "omniauth.auth" => auth }
      end
    end

    assert_redirected_to oauth_destination(existing)
    assert_equal existing.id, current_principal_id
    assert_equal(
      existing,
      Vertiso::Authentication::UserOauthAccount.find_by!(
        oauth_provider: @provider,
        provider_uid: "trusted-linked-collision"
      ).principal
    )
  end

  test "untrusted email collision does not link or sign in the existing principal" do
    github = create_github_provider
    existing = create_principal(
      email: "existing@example.com",
      user_name: "existing"
    )
    auth = oauth_auth(
      provider: "github",
      uid: "untrusted-collision",
      email: existing.email,
      all_emails: [
        {
          "email" => existing.email,
          "verified" => false,
          "primary" => true
        }
      ]
    )

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      get "/authentication/auth/github/callback",
          env: { "omniauth.auth" => auth }
    end

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_email_collision_untrusted",
        provider: github.display_name
      ),
      request.flash[:alert]
    )
    assert_nil current_principal_id
  end

  test "untrusted linked-email collision does not link or create a principal" do
    github = create_github_provider
    existing = create_principal(
      email: "canonical@example.com",
      user_name: "existing"
    )
    existing.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "existing-untrusted-linked-email",
      email: "linked@example.com"
    )
    auth = oauth_auth(
      provider: "github",
      uid: "untrusted-linked-collision",
      email: "linked@example.com",
      all_emails: [
        {
          "email" => "linked@example.com",
          "verified" => false,
          "primary" => true
        }
      ]
    )

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      get "/authentication/auth/github/callback",
          env: { "omniauth.auth" => auth }
    end

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_email_collision_untrusted",
        provider: github.display_name
      ),
      request.flash[:alert]
    )
    assert_nil current_principal_id
  end

  test "trusted email creates a confirmed principal through configured host attributes" do
    auth = oauth_auth(
      uid: "trusted-new",
      email: "new@example.com",
      name: "Configured OAuth Name"
    )
    auth.info[:admin] = true

    freeze_time do
      assert_difference(
        -> { User.count },
        1
      ) do
        get CALLBACK_PATH, env: { "omniauth.auth" => auth }
      end

      principal = User.find_by!(email: "new@example.com")

      assert_redirected_to oauth_destination(principal)
      assert_equal "oauth-user", principal.user_name
      assert_equal "Configured OAuth Name", principal.name
      assert_equal Time.current, principal.email_verified_at
      assert_not principal.has_attribute?(:admin)
      assert_equal principal.id, current_principal_id
    end
  end

  test "OAuth principal attribute hook rejects missing and non-hash contracts atomically" do
    invalid_hooks = {
      "missing" => nil,
      "noncallable" => "not-callable",
      "nil result" => ->(auth:) { nil },
      "non-hash result" => ->(auth:) { auth.info.name },
      "raising" => lambda do |auth:|
        raise RuntimeError, "attribute hook failed for #{auth.uid}"
      end
    }

    invalid_hooks.each_with_index do |(label, hook), index|
      Vertiso::Authentication.configuration.oauth_principal_attributes = hook

      assert_no_difference(
        [
          -> { User.count },
          -> { Vertiso::Authentication::UserOauthAccount.count }
        ],
        label
      ) do
        get CALLBACK_PATH,
            env: {
              "omniauth.auth" => oauth_auth(
                uid: "invalid-attributes-#{index}",
                email: "invalid-attributes-#{index}@example.com"
              )
            }
      end

      assert_response :internal_server_error, label
    end
  end

  test "OAuth user-name allocator rejects missing invalid and raising contracts atomically" do
    invalid_allocators = {
      "missing" => nil,
      "noncallable" => "not-callable",
      "nil result" => ->(principal_class:, candidate:) { nil },
      "non-string result" => lambda do |principal_class:, candidate:|
        [principal_class.name, candidate]
      end,
      "blank result" => ->(principal_class:, candidate:) { "  " },
      "raising" => lambda do |principal_class:, candidate:|
        raise RuntimeError,
              "allocator failed for #{principal_class.name}:#{candidate}"
      end
    }

    invalid_allocators.each_with_index do |(label, allocator), index|
      Vertiso::Authentication.configuration.oauth_user_name_allocator =
        allocator

      assert_no_difference(
        [
          -> { User.count },
          -> { Vertiso::Authentication::UserOauthAccount.count }
        ],
        label
      ) do
        get CALLBACK_PATH,
            env: {
              "omniauth.auth" => oauth_auth(
                uid: "invalid-allocator-#{index}",
                email: "invalid-allocator-#{index}@example.com"
              )
            }
      end

      assert_response :internal_server_error, label
    end
  end

  test "untrusted unique email creates an unconfirmed principal" do
    create_github_provider
    auth = oauth_auth(
      provider: "github",
      uid: "untrusted-new",
      email: "untrusted@example.com",
      name: "Untrusted OAuth",
      all_emails: [
        {
          "email" => "untrusted@example.com",
          "verified" => false,
          "primary" => true
        }
      ]
    )

    assert_difference(
      -> { User.count },
      1
    ) do
      get "/authentication/auth/github/callback",
          env: { "omniauth.auth" => auth }
    end

    principal = User.find_by!(email: "untrusted@example.com")

    assert_nil principal.email_verified_at
    assert_redirected_to oauth_destination(principal)
    assert_equal principal.id, current_principal_id
  end

  test "provider callback with malformed email cannot create a principal" do
    create_github_provider

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      get "/authentication/auth/github/callback",
          env: {
            "omniauth.auth" => oauth_auth(
              provider: "github",
              uid: "malformed-provider-email",
              email: "not-an-email"
            )
          }
    end

    assert_redirected_to LOGIN_PATH
    assert_predicate request.flash[:alert], :present?
  end

  test "untrusted OAuth signup enqueues confirmation while trusted signup does not" do
    create_github_provider
    untrusted_auth = oauth_auth(
      provider: "github",
      uid: "untrusted-confirmation",
      email: "untrusted-confirmation@example.com",
      all_emails: [
        {
          "email" => "untrusted-confirmation@example.com",
          "verified" => false,
          "primary" => true
        }
      ]
    )

    assert_enqueued_emails 1 do
      get "/authentication/auth/github/callback",
          env: { "omniauth.auth" => untrusted_auth }
    end

    delete "/authentication/logout"

    assert_no_enqueued_emails do
      get CALLBACK_PATH,
          env: {
            "omniauth.auth" => oauth_auth(
              uid: "trusted-no-confirmation",
              email: "trusted-no-confirmation@example.com"
            )
          }
    end
  end

  test "blank callback email enters a ten-minute pending interstitial" do
    create_github_provider
    auth = oauth_auth(
      provider: "github",
      uid: "blank-email",
      email: nil
    )

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      get "/authentication/auth/github/callback",
          env: { "omniauth.auth" => auth }
    end

    assert_redirected_to PROMPT_EMAIL_PATH

    get PROMPT_EMAIL_PATH

    assert_response :ok
    assert_includes response.body, "oauth_email[email]"

    travel 11.minutes do
      get PROMPT_EMAIL_PATH

      assert_redirected_to LOGIN_PATH
      assert_equal(
        I18n.t(
          "vertiso.authentication.sessions.oauth_email_session_expired"
        ),
        request.flash[:alert]
      )
    end
  end

  test "typed email remains untrusted even when the provider trusts callback emails" do
    observed_auth = nil
    Vertiso::Authentication.configuration.oauth_principal_attributes =
      lambda do |auth:|
        observed_auth = auth
        {
          name: auth.info.name.to_s.presence || "OAuth User"
        }
      end
    get CALLBACK_PATH,
        env: {
          "omniauth.auth" => oauth_auth(
            uid: "typed-email",
            email: nil,
            name: "Typed Email"
          )
        }

    assert_enqueued_emails 1 do
      assert_difference(
        -> { User.count },
        1
      ) do
        post COMPLETE_EMAIL_PATH,
             params: {
               oauth_email: {
                 email: " Typed@Example.com "
               }
             }
      end
    end

    principal = User.find_by!(email: "typed@example.com")
    account = principal.authentication_oauth_accounts.find_by!(
      oauth_provider: @provider,
      provider_uid: "typed-email"
    )

    assert_nil principal.email_verified_at
    assert_equal "callback-token", account.user_credentials["token"]
    assert_equal "google_oauth2", observed_auth.provider
    assert_equal "typed-email", observed_auth.uid
    assert_equal "typed@example.com", observed_auth.info.email
    assert_redirected_to oauth_destination(principal)
    assert_equal principal.id, current_principal_id
  end

  test "typed email collision is rejected without linking the pending identity" do
    existing = create_principal(
      email: "existing@example.com",
      user_name: "existing"
    )
    get CALLBACK_PATH,
        env: {
          "omniauth.auth" => oauth_auth(
            uid: "typed-collision",
            email: nil
          )
        }

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      post COMPLETE_EMAIL_PATH,
           params: {
             oauth_email: {
               email: existing.email
             }
           }
    end

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_email_collision_untrusted",
        provider: @provider.display_name
      ),
      request.flash[:alert]
    )
  end

  test "typed linked-email collision is rejected without creating records" do
    existing = create_principal(
      email: "canonical@example.com",
      user_name: "existing"
    )
    existing.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "existing-typed-linked-email",
      email: "linked@example.com"
    )
    get CALLBACK_PATH,
        env: {
          "omniauth.auth" => oauth_auth(
            uid: "typed-linked-collision",
            email: nil
          )
        }

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      post COMPLETE_EMAIL_PATH,
           params: {
             oauth_email: {
               email: "linked@example.com"
             }
           }
    end

    assert_redirected_to LOGIN_PATH
    assert_equal(
      I18n.t(
        "vertiso.authentication.sessions.oauth_email_collision_untrusted",
        provider: @provider.display_name
      ),
      request.flash[:alert]
    )
  end

  test "invalid typed email keeps the pending interstitial without creating records" do
    get CALLBACK_PATH,
        env: {
          "omniauth.auth" => oauth_auth(
            uid: "invalid-typed-email",
            email: nil
          )
        }

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      post COMPLETE_EMAIL_PATH,
           params: {
             oauth_email: {
               email: "not-an-email"
             }
           }
    end

    assert_response :unprocessable_content
    assert_equal(
      I18n.t("vertiso.authentication.sessions.email_invalid"),
      request.flash[:alert]
    )
  end

  test "database identity collision resolves the exact committed winner" do
    winner = create_principal(
      email: "winner@example.com",
      user_name: "winner"
    )
    target_uid = "unique-index-winner"
    uniqueness_validator = oauth_identity_uniqueness_validator
    inserted = false
    Vertiso::Authentication::UserOauthAccount.skip_callback(
      :validate,
      :before,
      uniqueness_validator
    )
    Vertiso::Authentication.configuration.oauth_principal_attributes =
      lambda do |auth:|
        unless inserted
          winner.authentication_oauth_accounts.create!(
            oauth_provider: @provider,
            provider_uid: target_uid,
            email: winner.email
          )
          inserted = true
        end

        {
          name: auth.info.name.to_s.presence || "OAuth User"
        }
      end

    assert_no_difference(-> { User.count }) do
      assert_difference(
        -> { Vertiso::Authentication::UserOauthAccount.count },
        1
      ) do
        get CALLBACK_PATH,
            env: {
              "omniauth.auth" => oauth_auth(
                uid: target_uid,
                email: "new-callback@example.com"
              )
            }
      end
    end

    account = Vertiso::Authentication::UserOauthAccount.find_by!(
      oauth_provider: @provider,
      provider_uid: target_uid
    )
    assert_equal winner, account.principal
    assert_redirected_to oauth_destination(winner)
    assert_equal winner.id, current_principal_id
  ensure
    if uniqueness_validator
      Vertiso::Authentication::UserOauthAccount.set_callback(
        :validate,
        :before,
        uniqueness_validator
      )
    end
  end

  test "principal and linked account creation are atomic" do
    callback = lambda do |account|
      if Thread.current[:reject_task_nine_oauth_account]
        account.errors.add(:base, "forced linked-account failure")
        raise ActiveRecord::RecordInvalid, account
      end
    end
    Vertiso::Authentication::UserOauthAccount.set_callback(
      :create,
      :before,
      :reject_task_nine_oauth_account,
      &callback
    )
    Thread.current[:reject_task_nine_oauth_account] = true

    assert_no_difference(
      [
        -> { User.count },
        -> { Vertiso::Authentication::UserOauthAccount.count }
      ]
    ) do
      get CALLBACK_PATH,
          env: {
            "omniauth.auth" => oauth_auth(
              uid: "atomic-rollback",
              email: "rollback@example.com"
            )
          }
    end

    assert_redirected_to LOGIN_PATH
  ensure
    Thread.current[:reject_task_nine_oauth_account] = nil
    Vertiso::Authentication::UserOauthAccount.skip_callback(
      :create,
      :before,
      :reject_task_nine_oauth_account
    )
  end

  test "duplicate callbacks are idempotent" do
    auth = oauth_auth(
      uid: "duplicate-callback",
      email: "duplicate@example.com"
    )

    2.times do
      get CALLBACK_PATH, env: { "omniauth.auth" => auth }
    end

    principal = User.find_by!(email: "duplicate@example.com")

    assert_equal 1,
                 principal.authentication_oauth_accounts.where(
                   oauth_provider: @provider,
                   provider_uid: "duplicate-callback"
                 ).count
    assert_equal principal.id, current_principal_id
  end

  private

  # Configures host-owned destinations for observable callback responses.
  #
  # @return [void]
  def configure_host
    Vertiso::Authentication.reset_configuration!
    Vertiso::Authentication.configure do |config|
      config.post_authentication_destination = lambda do |controller, principal|
        controller.main_app.signed_in_path(
          principal_id: principal.id,
          source: "oauth"
        )
      end
      config.confirmation_required_destination = lambda do |controller, principal|
        controller.main_app.signed_in_path(
          principal_id: principal.id,
          source: "oauth"
        )
      end
      config.oauth_principal_attributes = lambda do |auth:|
        {
          name: auth.info.name.to_s.presence || "OAuth User"
        }
      end
      config.oauth_user_name_allocator = lambda do |principal_class:, candidate:|
        normalized = candidate.to_s.strip.downcase
        next normalized unless principal_class.exists?(user_name: normalized)

        "#{normalized}-#{SecureRandom.alphanumeric(6).downcase}"
      end
    end
  end

  # Creates the production-compatible GitHub provider.
  #
  # @return [Vertiso::Authentication::OauthProvider]
  def create_github_provider
    Vertiso::Authentication::OauthProvider.create!(
      name: "github",
      display_name: "GitHub",
      trusts_email: false
    )
  end

  # Creates a standard-host principal.
  #
  # @param email [String]
  # @param user_name [String]
  # @return [User]
  def create_principal(email:, user_name:)
    User.create!(
      email:,
      user_name:,
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
  end

  # Signs a principal in through the real password-session endpoint.
  #
  # @param principal [User]
  # @return [void]
  def sign_in(principal)
    post LOGIN_PATH, params: {
      session: {
        login: principal.email,
        password: PASSWORD
      }
    }

    assert_redirected_to oauth_destination(principal)
  end

  # Returns the host-visible current principal.
  #
  # @return [Integer, nil]
  def current_principal_id
    get STATE_PATH
    response.parsed_body["principal_id"]
  end

  # Returns the provider-identity uniqueness validator callback.
  #
  # @return [ActiveRecord::Validations::UniquenessValidator]
  def oauth_identity_uniqueness_validator
    Vertiso::Authentication::UserOauthAccount.validators_on(
      :provider_uid
    ).find do |validator|
      validator.is_a?(
        ActiveRecord::Validations::UniquenessValidator
      )
    end
  end

  # Returns the configured host destination for a principal.
  #
  # @param principal [User]
  # @return [String]
  def oauth_destination(principal)
    "/signed-in?principal_id=#{principal.id}&source=oauth"
  end

  # Runs a block under an exact Rails environment inquiry.
  #
  # @param name [String]
  # @yieldreturn [Object]
  # @return [Object]
  def with_rails_environment(name, &)
    environment = ActiveSupport::EnvironmentInquirer.new(name)
    environment_was_defined = Rails.instance_variable_defined?(:@_env)
    original_environment = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(:@_env, environment)
    yield
  ensure
    if environment_was_defined
      Rails.instance_variable_set(:@_env, original_environment)
    else
      Rails.remove_instance_variable(:@_env)
    end
  end

  # Builds a complete production-shaped OmniAuth callback hash.
  #
  # @param provider [String]
  # @param uid [String]
  # @param email [String]
  # @param name [String]
  # @param token [String]
  # @param refresh_token [String, nil]
  # @param all_emails [Array<Hash>, nil]
  # @return [OmniAuth::AuthHash]
  def oauth_auth(
    provider: "google_oauth2",
    uid: "provider-uid",
    email: "person@example.com",
    name: "OAuth User",
    token: "callback-token",
    refresh_token: "callback-refresh-token",
    all_emails: nil
  )
    extra = {
      raw_info: {
        "id" => uid,
        "email" => email
      }
    }
    extra[:all_emails] = all_emails unless all_emails.nil?

    OmniAuth::AuthHash.new(
      provider:,
      uid:,
      info: {
        email:,
        name:,
        nickname: "oauth-user",
        image: "https://example.com/avatar.png"
      },
      credentials: {
        token:,
        refresh_token:,
        expires_at: 1_893_456_000,
        expires: true,
        scope: "openid email profile"
      },
      extra:
    )
  end
end
