# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "component_test_helper"

class VertisoAuthenticationPasswordFieldComponentTest < ActiveSupport::TestCase
  include VertisoAuthenticationComponentTestHelper

  test "renders required new-password fields from the supplied form" do
    principal = User.new
    form = ActionView::Helpers::FormBuilder.new(
      :registration,
      principal,
      vc_test_controller.view_context,
      {}
    )

    render_inline(
      Vertiso::Authentication::Auth::PasswordFieldComponent.new(
        form:,
        required: true
      )
    )

    document = rendered_document
    password = document.at_css("input[name='registration[password]']")
    confirmation = document.at_css(
      "input[name='registration[password_confirmation]']"
    )

    assert_equal "password", password["type"]
    assert_equal "new-password", password["autocomplete"]
    assert password.key?("required")
    assert_equal "new-password", confirmation["autocomplete"]
    assert confirmation.key?("required")
    assert_equal "Password", document.at_css("label[for='registration_password']").text.strip
    assert_equal(
      "Password confirmation",
      document.at_css("label[for='registration_password_confirmation']").text.strip
    )
  end
end
