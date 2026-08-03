# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "omniauth"

class VertisoAuthenticationOauthProviderTest < ActiveSupport::TestCase
  test "Google trusts a present callback email" do
    provider = oauth_provider(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )

    assert_equal true,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "google_oauth2",
                     email: "person@example.com"
                   )
                 )
  end

  test "Google rejects a blank callback email" do
    provider = oauth_provider(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(provider: "google_oauth2", email: "")
                 )
  end

  test "Apple trusts a present callback email" do
    provider = oauth_provider(
      name: "apple",
      display_name: "Apple",
      trusts_email: true
    )

    assert_equal true,
                 provider.email_trusted_for?(
                   auth_hash(provider: "apple", email: "relay@example.com")
                 )
  end

  test "Apple rejects a blank callback email" do
    provider = oauth_provider(
      name: "apple",
      display_name: "Apple",
      trusts_email: true
    )

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(provider: "apple", email: nil)
                 )
  end

  test "GitHub trusts a verified primary email matching the callback" do
    provider = github_provider
    all_emails = [
      {
        "email" => "person@example.com",
        "verified" => true,
        "primary" => true
      }
    ]

    assert_equal true,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "github",
                     email: "person@example.com",
                     all_emails:
                   )
                 )
  end

  test "GitHub rejects a verified non-primary callback email" do
    provider = github_provider
    all_emails = [
      {
        "email" => "person@example.com",
        "verified" => true,
        "primary" => false
      }
    ]

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "github",
                     email: "person@example.com",
                     all_emails:
                   )
                 )
  end

  test "GitHub rejects an unverified primary callback email" do
    provider = github_provider
    all_emails = [
      {
        "email" => "person@example.com",
        "verified" => false,
        "primary" => true
      }
    ]

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "github",
                     email: "person@example.com",
                     all_emails:
                   )
                 )
  end

  test "GitHub rejects a verified primary email that does not match the callback" do
    provider = github_provider
    all_emails = [
      {
        "email" => "other@example.com",
        "verified" => true,
        "primary" => true
      }
    ]

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "github",
                     email: "person@example.com",
                     all_emails:
                   )
                 )
  end

  test "GitHub rejects a callback missing all_emails" do
    provider = github_provider

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "github",
                     email: "person@example.com"
                   )
                 )
  end

  test "GitHub rejects a blank callback email despite a verified primary entry" do
    provider = github_provider
    all_emails = [
      {
        "email" => "person@example.com",
        "verified" => true,
        "primary" => true
      }
    ]

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "github",
                     email: " ",
                     all_emails:
                   )
                 )
  end

  test "other provider defaults a present callback email to untrusted" do
    provider = oauth_provider(
      name: "other",
      display_name: "Other",
      trusts_email: false
    )

    assert_equal false,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "other",
                     email: "person@example.com"
                   )
                 )
  end

  test "other provider explicitly configured to trust email trusts a present callback email" do
    provider = oauth_provider(
      name: "other",
      display_name: "Other",
      trusts_email: true
    )

    assert_equal true,
                 provider.email_trusted_for?(
                   auth_hash(
                     provider: "other",
                     email: "person@example.com"
                   )
                 )
  end

  private

  # Creates a persisted provider with explicit trust configuration.
  #
  # @param name [String]
  # @param display_name [String]
  # @param trusts_email [Boolean]
  # @return [Vertiso::Authentication::OauthProvider]
  def oauth_provider(name:, display_name:, trusts_email:)
    Vertiso::Authentication::OauthProvider.create!(
      name:,
      display_name:,
      trusts_email:
    )
  end

  # Creates the production-compatible GitHub provider.
  #
  # @return [Vertiso::Authentication::OauthProvider]
  def github_provider
    oauth_provider(
      name: "github",
      display_name: "GitHub",
      trusts_email: false
    )
  end

  # Builds a complete callback payload using OmniAuth's production hash type.
  #
  # @param provider [String]
  # @param email [String, nil]
  # @param all_emails [Array<Hash>, nil]
  # @return [OmniAuth::AuthHash]
  def auth_hash(provider:, email:, all_emails: nil)
    extra = {
      raw_info: {
        id: "provider-uid-123",
        email:,
        login: "oauth-user"
      }
    }
    extra[:all_emails] = all_emails unless all_emails.nil?

    OmniAuth::AuthHash.new(
      provider:,
      uid: "provider-uid-123",
      info: {
        name: "OAuth User",
        email:,
        nickname: "oauth-user",
        first_name: "OAuth",
        last_name: "User",
        image: "https://example.com/avatar.png",
        urls: {
          "Profile" => "https://example.com/oauth-user"
        }
      },
      credentials: {
        token: "access-token",
        refresh_token: "refresh-token",
        expires_at: 1_893_456_000,
        expires: true,
        scope: "openid email profile"
      },
      extra:
    )
  end
end
