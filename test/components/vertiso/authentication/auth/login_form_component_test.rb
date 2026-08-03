# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "component_test_helper"

class VertisoAuthenticationLoginFormComponentTest < ActiveSupport::TestCase
  include VertisoAuthenticationComponentTestHelper

  test "renders the password login semantics and configured destinations" do
    provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      active: true,
      trusts_email: true
    )

    render_inline(
      Vertiso::Authentication::Auth::LoginFormComponent.new(
        login: "person@example.com",
        home_path: "/",
        session_path: "/authentication/login",
        forgot_password_path: "/authentication/forgot-password",
        registration_path: "/authentication/register",
        providers: [provider],
        oauth_path: ->(name) { "/auth/#{name}" },
        errors: ["Invalid login or password."]
      )
    )

    document = rendered_document
    form = document.at_css("form[action='/authentication/login']")
    login = form.at_css("input[name='session[login]']")
    password = form.at_css("input[name='session[password]']")

    assert_equal "post", form["method"]
    assert_equal "username", login["autocomplete"]
    assert login.key?("required")
    assert_equal "person@example.com", login["value"]
    assert_equal "current-password", password["autocomplete"]
    assert password.key?("required")
    assert_equal "Email or user name", form.at_css("label[for='session_login']").text.strip
    assert_equal "Password", form.at_css("label[for='session_password']").text.strip
    assert_equal "alert", document.at_css("[role='alert']")["role"]
    assert_includes document.at_css("[role='alert']").text, "Invalid login or password."
    assert_equal(
      "/authentication/forgot-password",
      link_with_text(document, "Forgot your password?")["href"]
    )
    assert_equal(
      "/authentication/register",
      link_with_text(document, "Create account")["href"]
    )
    assert document.at_css("form[action='/auth/google_oauth2']")
  end

  test "forwards the development-only provider option explicitly" do
    render_inline(
      Vertiso::Authentication::Auth::LoginFormComponent.new(
        home_path: "/",
        session_path: "/authentication/login",
        forgot_password_path: "/authentication/forgot-password",
        registration_path: "/authentication/register",
        providers: [],
        oauth_path: ->(name) { "/auth/#{name}" },
        include_developer: true
      )
    )

    assert rendered_document.at_css("form[action='/auth/developer']")
  end
end
