# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationGemspecTest < ActiveSupport::TestCase
  test "declares the MIT license" do
    assert_equal "MIT", Gem::Specification.load(gemspec_path).license
  end

  private

  # Returns the path to the gem specification under test.
  #
  # @return [String] absolute path to the gem specification
  def gemspec_path
    File.expand_path("../../../../vertiso-authentication.gemspec", __dir__)
  end
end
