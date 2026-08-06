# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "component_test_helper"

class VertisoAuthenticationOauthProvidersComponentTest < ActiveSupport::TestCase
  include VertisoAuthenticationComponentTestHelper

  test "renders explicit providers and linked identities with configured routes" do
    principal = User.create!(
      email: "person@example.com",
      user_name: "person",
      password: "StrongPassword123!"
    )
    provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      active: true,
      trusts_email: true
    )
    account = Vertiso::Authentication::UserOauthAccount.create!(
      principal:,
      oauth_provider: provider,
      provider_uid: "google-123",
      email: "person@example.com"
    )

    render_inline(
      Vertiso::Authentication::Auth::OauthProvidersComponent.new(
        providers: [provider],
        linked_accounts: [account],
        oauth_path: ->(name) { "/auth/#{name}" },
        unlink_path: ->(identity) { "/authentication/auth/oauth-accounts/#{identity.id}" },
        include_developer: true
      )
    )

    document = rendered_document
    google_form = document.at_css("form[action='/auth/google_oauth2']")
    developer_form = document.at_css("form[action='/auth/developer']")
    unlink_form = document.at_css(
      "form[action='/authentication/auth/oauth-accounts/#{account.id}']"
    )

    assert_equal "post", google_form["method"]
    assert_includes google_form.text, "Continue with Google"
    assert_equal "post", developer_form["method"]
    assert_includes developer_form.text, "Continue with Developer"
    assert_includes document.at_css("li##{ActionView::RecordIdentifier.dom_id(account)}").text, "person@example.com"
    assert_equal "post", unlink_form["method"]
    assert_equal "delete", unlink_form.at_css("input[name='_method']")["value"]
    assert_equal "Unlink Google", unlink_form.at_css("button")["aria-label"]
  end

  test "renders host-configured icons without provider-name branching" do
    principal = User.create!(
      email: "icons@example.com",
      user_name: "icons",
      password: "StrongPassword123!"
    )
    icon_provider = Vertiso::Authentication::OauthProvider.create!(
      name: "enterprise_login",
      display_name: "Enterprise Login",
      configuration: {
        "icon_class" => "host-icon host-icon-enterprise"
      }
    )
    plain_provider = Vertiso::Authentication::OauthProvider.create!(
      name: "plain_login",
      display_name: "Plain Login"
    )
    account = principal.authentication_oauth_accounts.create!(
      oauth_provider: icon_provider,
      provider_uid: "enterprise-123"
    )

    render_inline(
      Vertiso::Authentication::Auth::OauthProvidersComponent.new(
        providers: [icon_provider, plain_provider],
        linked_accounts: [account],
        oauth_path: ->(name) { "/auth/#{name}" },
        unlink_path: ->(identity) { "/oauth-accounts/#{identity.id}" }
      )
    )

    document = rendered_document
    icon_button = document.at_css(
      "form[action='/auth/enterprise_login'] button"
    )
    plain_button = document.at_css("form[action='/auth/plain_login'] button")
    account_row = document.at_css(
      "li##{ActionView::RecordIdentifier.dom_id(account)}"
    )

    assert icon_button.at_css("i.host-icon.host-icon-enterprise")
    assert account_row.at_css("i.host-icon.host-icon-enterprise")
    assert_nil plain_button.at_css("i")
  end
end
