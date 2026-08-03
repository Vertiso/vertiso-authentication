# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "view_component/test_helpers"

module VertisoAuthenticationComponentTestHelper
  include ViewComponent::TestHelpers

  private

  def rendered_document
    Nokogiri::HTML5.fragment(rendered_content)
  end

  def link_with_text(document, text)
    document.at_xpath(".//a[normalize-space(.)=#{text.to_json}]")
  end
end
