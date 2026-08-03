# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "component_test_helper"

class VertisoAuthenticationThemeTest < ActiveSupport::TestCase
  include VertisoAuthenticationComponentTestHelper

  setup do
    Vertiso::Authentication.reset_configuration!
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "default theme renders neutral semantic values" do
    render_inline(
      Vertiso::Authentication::Auth::ShellComponent.new(
        title: "Sign in",
        subtitle: "Continue",
        home_path: "/"
      )
    ) { "FORM" }

    document = rendered_document

    assert_includes document.at_css("main")["class"], "font-sans"
    assert_includes document.at_css("main")["class"], "bg-white"
    assert_includes document.at_css("h1")["class"], "text-slate-950"
    assert_includes document.at_css(".vertiso-auth-shell__surface")["class"], "rounded-lg"
  end

  test "GoalMindr-compatible theme renders its glass authentication semantics" do
    Vertiso::Authentication.configuration.theme =
      Vertiso::Authentication::Theme.goalmindr

    render_login_form
    document = rendered_document

    assert_includes document.at_css("main")["class"], "font-sans"
    assert_includes document.at_css("main")["class"], "bg-white"
    assert_includes document.at_css(".vertiso-auth-shell__surface")["class"], "rounded-2xl"
    assert_includes document.at_css("input[name='session[login]']")["class"], "rounded-xl"
    assert_includes document.at_css("input[type='submit']")["class"], "bg-indigo-600"
  end

  test "Momento-compatible theme renders VDS semantic values" do
    Vertiso::Authentication.configuration.theme =
      Vertiso::Authentication::Theme.momento

    render_login_form
    document = rendered_document

    assert_includes document.at_css("main")["class"], "font-poppins"
    assert_includes document.at_css("main")["class"], "bg-vds-black"
    assert_includes document.at_css("h1")["class"], "text-vds-text"
    assert_includes document.at_css("input[name='session[login]']")["class"], "border-vds-border"
    assert_includes document.at_css("input[type='submit']")["class"], "btn-primary"
  end

  test "host can replace every semantic value without copying views" do
    Vertiso::Authentication.configuration.theme =
      Vertiso::Authentication::Theme.new(
        font: "font-host",
        foreground: "text-host",
        muted: "text-host-muted",
        border: "border-host",
        surface: "bg-host",
        accent: "text-host-accent",
        danger: "text-host-danger",
        focus: "focus:ring-host",
        spacing: "p-host",
        radius: "rounded-host",
        button: "button-host",
        field: "field-host"
      )

    render_login_form(errors: ["No match"])
    document = rendered_document

    assert_includes document.at_css("main")["class"], "font-host"
    assert_includes document.at_css("h1")["class"], "text-host"
    assert_includes document.at_css(".vertiso-auth-shell__subtitle")["class"], "text-host-muted"
    assert_includes document.at_css(".vertiso-auth-shell__surface")["class"], "border-host"
    assert_includes document.at_css(".vertiso-auth-shell__surface")["class"], "bg-host"
    assert_includes document.at_css(".vertiso-auth-shell__home")["class"], "text-host-accent"
    assert_includes document.at_css("[role='alert']")["class"], "text-host-danger"
    assert_includes document.at_css("input[name='session[login]']")["class"], "focus:ring-host"
    assert_includes document.at_css(".vertiso-auth-shell__surface")["class"], "p-host"
    assert_includes document.at_css(".vertiso-auth-shell__surface")["class"], "rounded-host"
    assert_includes document.at_css("input[type='submit']")["class"], "button-host"
    assert_includes document.at_css("input[name='session[login]']")["class"], "field-host"
  end

  private

  def render_login_form(errors: [])
    render_inline(
      Vertiso::Authentication::Auth::LoginFormComponent.new(
        home_path: "/",
        session_path: "/authentication/login",
        forgot_password_path: "/authentication/forgot-password",
        registration_path: "/authentication/register",
        providers: [],
        oauth_path: ->(name) { "/auth/#{name}" },
        errors:
      )
    )
  end
end
