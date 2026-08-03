# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "component_test_helper"

class VertisoAuthenticationShellComponentTest < ActiveSupport::TestCase
  include VertisoAuthenticationComponentTestHelper

  test "renders a labelled authentication main region and caller content" do
    render_inline(
      Vertiso::Authentication::Auth::ShellComponent.new(
        title: "Welcome back",
        subtitle: "Sign in to continue",
        home_path: "/"
      )
    ) { "<p>FORM-CONTENT</p>".html_safe }

    document = rendered_document
    main = document.at_css("main[aria-labelledby='vertiso-auth-title']")

    assert main
    assert_equal "Welcome back", main.at_css("h1#vertiso-auth-title").text.strip
    assert_includes main.text, "Sign in to continue"
    assert_includes main.text, "FORM-CONTENT"
    assert_equal "/", document.at_css("a[aria-label='Home']")["href"]
  end
end
