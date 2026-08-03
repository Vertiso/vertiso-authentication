# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "component_test_helper"

class VertisoAuthenticationSignupFormComponentTest < ActiveSupport::TestCase
  include VertisoAuthenticationComponentTestHelper

  test "renders mapped signup fields, principal errors, and configured destinations" do
    principal = User.new(
      email: "person@example.com",
      user_name: "person"
    )
    principal.errors.add(:email, "is invalid")

    render_inline(
      Vertiso::Authentication::Auth::SignupFormComponent.new(
        principal:,
        home_path: "/",
        registration_path: "/authentication/register",
        login_path: "/authentication/login",
        providers: [],
        oauth_path: ->(name) { "/auth/#{name}" }
      )
    )

    document = rendered_document
    form = document.at_css("form[action='/authentication/register']")
    email = form.at_css("input[name='registration[email]']")
    user_name = form.at_css("input[name='registration[user_name]']")

    assert_equal "post", form["method"]
    assert_equal "email", email["type"]
    assert_equal "email", email["autocomplete"]
    assert email.key?("required")
    assert_equal "person@example.com", email["value"]
    assert_equal "username", user_name["autocomplete"]
    assert user_name.key?("required")
    assert_equal "person", user_name["value"]
    assert_includes document.at_css("[role='alert']").text, "Email is invalid"
    assert_equal(
      "/authentication/login",
      link_with_text(document, "Sign in")["href"]
    )
    assert form.at_css("input[name='registration[password]']")
    assert form.at_css("input[name='registration[password_confirmation]']")
  end

  test "forwards the development-only provider option explicitly" do
    render_inline(
      Vertiso::Authentication::Auth::SignupFormComponent.new(
        principal: User.new,
        home_path: "/",
        registration_path: "/authentication/register",
        login_path: "/authentication/login",
        providers: [],
        oauth_path: ->(name) { "/auth/#{name}" },
        include_developer: true
      )
    )

    assert rendered_document.at_css("form[action='/auth/developer']")
  end
end
