# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationMappedUserOauthAccountTest < ActiveSupport::TestCase
  setup do
    skip "requires the mapped dummy host" unless User.attribute_names.include?("handle")

    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end
    @provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "authenticates a mapped principal by linked provider email" do
    principal = create_principal(
      email: "person@example.com",
      handle: "person"
    )
    principal.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "mapped-linked-login",
      email: " Linked@Example.com "
    )

    assert_equal principal,
                 User.authenticate(
                   "LINKED@example.com",
                   "TestPassword1234!"
                 )
  end

  test "mapped canonical handle takes precedence without password fallthrough" do
    direct = create_principal(
      email: "direct@example.com",
      handle: "shared-login",
      password: "DirectPassword1234!"
    )
    linked = create_principal(
      email: "linked@example.com",
      handle: "linked",
      password: "LinkedPassword1234!"
    )
    linked.authentication_oauth_accounts.create!(
      oauth_provider: @provider,
      provider_uid: "mapped-shared-login",
      email: "shared-login"
    )

    assert_equal direct,
                 User.authenticate(
                   "shared-login",
                   "DirectPassword1234!"
                 )
    assert_equal false,
                 User.authenticate(
                   "shared-login",
                   "LinkedPassword1234!"
                 )
  end

  private

  # Creates a mapped-host principal.
  #
  # @param email [String]
  # @param handle [String]
  # @param password [String]
  # @return [User]
  def create_principal(email:, handle:, password: "TestPassword1234!")
    User.create!(
      email:,
      handle:,
      password:,
      password_confirmation: password
    )
  end
end
