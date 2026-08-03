# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "omniauth"

class VertisoAuthenticationUserOauthAccountTest < ActiveSupport::TestCase
  setup do
    @provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )
    @principal = create_principal(
      email: "person@example.com",
      user_name: "person"
    )
  end

  test "permits several provider identities for one principal" do
    github = Vertiso::Authentication::OauthProvider.create!(
      name: "github",
      display_name: "GitHub",
      trusts_email: false
    )

    first = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "google-1"
    )
    second = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "google-2"
    )
    third = @principal.authentication_oauth_accounts.create!(
      oauth_provider: github,
      provider_uid: "github-1"
    )

    assert_equal [first, second, third],
                 @principal.authentication_oauth_accounts.order(:id).to_a
  end

  test "prevents a provider identity from belonging to another principal" do
    @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "shared-provider-uid"
    )
    other = create_principal(
      email: "other@example.com",
      user_name: "other"
    )
    collision = other.authentication_oauth_accounts.build(
      oauth_provider: @provider,
      provider_uid: "shared-provider-uid"
    )

    assert_not collision.valid?
    assert_includes collision.errors[:provider_uid], "has already been taken"
    assert_raises ActiveRecord::RecordNotUnique do
      collision.save!(validate: false)
    end
  end

  test "retains callback profile and credentials as wholesale hashes" do
    initial_auth = auth_hash(
      token: "initial-access-token",
      refresh_token: "initial-refresh-token"
    )
    account = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: initial_auth.uid,
      user_info: initial_auth.info.to_hash,
      user_credentials: initial_auth.credentials.to_hash
    )

    assert_equal(
      {
        "name" => "OAuth User",
        "email" => "person@example.com",
        "nickname" => "oauth-user",
        "first_name" => "OAuth",
        "last_name" => "User",
        "image" => "https://example.com/avatar.png",
        "urls" => {
          "Profile" => "https://example.com/oauth-user"
        }
      },
      account.reload.user_info
    )
    assert_equal(
      {
        "token" => "initial-access-token",
        "refresh_token" => "initial-refresh-token",
        "expires_at" => 1_893_456_000,
        "expires" => true,
        "scope" => "openid email profile"
      },
      account.user_credentials
    )

    refreshed_auth = auth_hash(
      token: "replacement-access-token",
      refresh_token: nil
    )
    account.update!(
      user_credentials: refreshed_auth.credentials.to_hash
    )

    assert_equal(
      {
        "token" => "replacement-access-token",
        "refresh_token" => nil,
        "expires_at" => 1_893_456_000,
        "expires" => true,
        "scope" => "openid email profile"
      },
      account.reload.user_credentials
    )
  end

  test "normalizes an optional linked email without making it unique" do
    first = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "first-email",
      email: " Linked@Example.com "
    )
    other = create_principal(
      email: "other@example.com",
      user_name: "other"
    )
    second = other.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "second-email",
      email: "linked@example.com"
    )
    blank = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "blank-email",
      email: nil
    )

    assert_equal "linked@example.com", first.reload.email
    assert_predicate second, :persisted?
    assert_nil blank.reload.email
  end

  test "authenticates by a normalized linked provider email" do
    @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "linked-login",
      email: " Linked@Example.com "
    )

    assert_equal @principal,
                 User.authenticate(
                   " LINKED@example.com ",
                   "TestPassword1234!"
                 )
  end

  test "canonical principal email takes precedence over linked email" do
    direct = create_principal(
      email: "shared@example.com",
      user_name: "direct",
      password: "DirectPassword1234!"
    )
    @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "linked-shared-email",
      email: "shared@example.com"
    )

    assert_equal direct,
                 User.authenticate(
                   "shared@example.com",
                   "DirectPassword1234!"
                 )
  end

  test "wrong canonical principal password does not fall through to linked email" do
    create_principal(
      email: "shared@example.com",
      user_name: "direct",
      password: "DirectPassword1234!"
    )
    linked = create_principal(
      email: "linked-owner@example.com",
      user_name: "linked-owner",
      password: "LinkedPassword1234!"
    )
    linked.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "linked-shared-email",
      email: "shared@example.com"
    )

    assert_equal false,
                 User.authenticate(
                   "shared@example.com",
                   "LinkedPassword1234!"
                 )
  end

  test "canonical principal user name takes precedence over linked email" do
    direct = create_principal(
      email: "direct@example.com",
      user_name: "shared-login",
      password: "DirectPassword1234!"
    )
    @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "linked-shared-user-name",
      email: "shared-login"
    )

    assert_equal direct,
                 User.authenticate(
                   "shared-login",
                   "DirectPassword1234!"
                 )
  end

  private

  # Creates a standard-host principal.
  #
  # @param email [String]
  # @param user_name [String]
  # @param password [String]
  # @return [User]
  def create_principal(email:, user_name:, password: "TestPassword1234!")
    User.create!(
      email:,
      user_name:,
      password:,
      password_confirmation: password
    )
  end

  # Builds a complete callback payload using OmniAuth's production hash type.
  #
  # @param token [String]
  # @param refresh_token [String, nil]
  # @return [OmniAuth::AuthHash]
  def auth_hash(token:, refresh_token:)
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "provider-uid-123",
      info: {
        name: "OAuth User",
        email: "person@example.com",
        nickname: "oauth-user",
        first_name: "OAuth",
        last_name: "User",
        image: "https://example.com/avatar.png",
        urls: {
          "Profile" => "https://example.com/oauth-user"
        }
      },
      credentials: {
        token:,
        refresh_token:,
        expires_at: 1_893_456_000,
        expires: true,
        scope: "openid email profile"
      },
      extra: {
        raw_info: {
          id: "provider-uid-123",
          email: "person@example.com"
        }
      }
    )
  end
end
