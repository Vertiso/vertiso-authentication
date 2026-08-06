# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "omniauth"

# Alternate polymorphic principal used to prove host-bound authentication.
class AlternateAuthenticationPrincipal < ApplicationRecord
  self.table_name = "users"

  has_secure_password
end

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

  test "encrypts provider credentials at rest while preserving hash access" do
    account = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "encrypted-provider-credentials",
      user_credentials: {
        "token" => "database-secret-token",
        "refresh_token" => "database-secret-refresh-token"
      }
    )

    raw_credentials = raw_user_credentials(account)

    assert_not_includes raw_credentials, "database-secret-token"
    assert_not_includes raw_credentials, "database-secret-refresh-token"
    assert_equal(
      {
        "token" => "database-secret-token",
        "refresh_token" => "database-secret-refresh-token"
      },
      account.reload.user_credentials
    )
  end

  test "rewrites legacy plaintext credentials during an encryption transition" do
    account = @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "legacy-plaintext-credentials"
    )
    legacy_credentials = {
      "token" => "legacy-plaintext-token",
      "refresh_token" => "legacy-plaintext-refresh-token"
    }

    ActiveRecord::Encryption.without_encryption do
      account.update!(user_credentials: legacy_credentials)
    end
    assert_includes raw_user_credentials(account), "legacy-plaintext-token"

    with_unencrypted_data_support do
      assert_equal legacy_credentials, account.reload.user_credentials

      account.encrypt
    end

    assert_not_includes raw_user_credentials(account), "legacy-plaintext-token"
    assert_equal legacy_credentials, account.reload.user_credentials
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

  test "does not authenticate a linked account owned by another principal type" do
    alternate = AlternateAuthenticationPrincipal.create!(
      email: "alternate@example.com",
      user_name: "alternate",
      password: "AlternatePassword1234!",
      password_confirmation: "AlternatePassword1234!"
    )
    Vertiso::Authentication::UserOauthAccount.create!(
      principal: alternate,
      oauth_provider: @provider,
      provider_uid: "alternate-principal",
      email: "cross-type@example.com"
    )

    assert_nil User.authenticate(
      "cross-type@example.com",
      "AlternatePassword1234!"
    )
  end

  test "rejects a blank login before linked-account lookup" do
    @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "blank-linked-login",
      email: " "
    )

    assert_nil User.authenticate(" ", "TestPassword1234!")
    assert_nil User.authenticate(nil, "TestPassword1234!")
  end

  test "rejects a blank password before canonical or linked lookup" do
    @principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "linked-blank-password",
      email: "linked-password@example.com"
    )

    assert_nil User.authenticate("person@example.com", nil)
    assert_nil User.authenticate("person@example.com", " ")
    assert_nil User.authenticate("linked-password@example.com", "")
    assert_nil User.authenticate("linked-password@example.com", " ")
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

  # Returns the database representation without model decryption.
  #
  # @param account [Vertiso::Authentication::UserOauthAccount]
  # @return [String]
  def raw_user_credentials(account)
    ActiveRecord::Base.connection.select_value(
      <<~SQL.squish
        SELECT user_credentials
        FROM vertiso_authentication_user_oauth_accounts
        WHERE id = #{Integer(account.id)}
      SQL
    ).to_s
  end

  # Temporarily permits Rails to read a legacy plaintext encrypted attribute.
  #
  # @yieldreturn [void]
  # @return [void]
  def with_unencrypted_data_support
    configuration = ActiveRecord::Encryption.config
    previous_value = configuration.support_unencrypted_data
    configuration.support_unencrypted_data = true
    yield
  ensure
    configuration.support_unencrypted_data = previous_value
  end
end
