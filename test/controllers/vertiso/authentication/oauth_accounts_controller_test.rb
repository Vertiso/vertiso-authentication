# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationOauthAccountsControllerTest < ActionDispatch::IntegrationTest
  LOGIN_PATH = "/authentication/login"
  PASSWORD = "TestPassword1234!"

  setup do
    configure_host
    @provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )
    @principal = create_principal(
      email: "owner@example.com",
      user_name: "owner"
    )
    @other_principal = create_principal(
      email: "other@example.com",
      user_name: "other"
    )
    @account = create_account(
      principal: @principal,
      uid: "owner-account"
    )
    @other_account = create_account(
      principal: @other_principal,
      uid: "other-account"
    )
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "destroys an account owned by the current principal" do
    sign_in(@principal)

    assert_difference(
      -> { Vertiso::Authentication::UserOauthAccount.count },
      -1
    ) do
      delete oauth_account_path(@account)
    end

    assert_redirected_to oauth_destination(@principal)
    assert_equal(
      I18n.t(
        "vertiso.authentication.oauth_accounts.unlinked",
        provider: @provider.display_name
      ),
      request.flash[:notice]
    )
    assert_not Vertiso::Authentication::UserOauthAccount.exists?(@account.id)
  end

  test "cannot destroy an account owned by another principal" do
    sign_in(@principal)

    assert_no_difference(
      -> { Vertiso::Authentication::UserOauthAccount.count }
    ) do
      delete oauth_account_path(@other_account)
    end

    assert_redirected_to oauth_destination(@principal)
    assert_equal(
      I18n.t("vertiso.authentication.oauth_accounts.unlink_failed"),
      request.flash[:alert]
    )
    assert Vertiso::Authentication::UserOauthAccount.exists?(
      @other_account.id
    )
  end

  test "anonymous unlink cannot destroy any account" do
    assert_no_difference(
      -> { Vertiso::Authentication::UserOauthAccount.count }
    ) do
      delete oauth_account_path(@account)
    end

    assert_redirected_to LOGIN_PATH
    assert Vertiso::Authentication::UserOauthAccount.exists?(@account.id)
  end

  private

  # Configures the host destination used after account management.
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
    end
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

  # Creates a linked OAuth identity.
  #
  # @param principal [User]
  # @param uid [String]
  # @return [Vertiso::Authentication::UserOauthAccount]
  def create_account(principal:, uid:)
    principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: uid
    )
  end

  # Signs a principal in through the production password flow.
  #
  # @param principal [User]
  # @return [void]
  def sign_in(principal)
    post LOGIN_PATH,
         params: {
           session: {
             login: principal.email,
             password: PASSWORD
           }
         }
  end

  # Returns the mounted engine unlink path.
  #
  # @param account [Vertiso::Authentication::UserOauthAccount]
  # @return [String]
  def oauth_account_path(account)
    "/authentication/auth/oauth-accounts/#{account.id}"
  end

  # Returns the configured host destination.
  #
  # @param principal [User]
  # @return [String]
  def oauth_destination(principal)
    "/signed-in?principal_id=#{principal.id}&source=oauth"
  end
end
