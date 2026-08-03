# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationGemspecTest < ActiveSupport::TestCase
  test "declares the MIT license" do
    assert_equal "MIT", Gem::Specification.load(gemspec_path).license
  end

  test "keeps representative database adapters development only" do
    specification = Gem::Specification.load(gemspec_path)
    development_dependencies = specification.development_dependencies.map(&:name)
    runtime_dependencies = specification.runtime_dependencies.map(&:name)

    assert_includes development_dependencies, "sqlite3"
    assert_includes development_dependencies, "pg"
    refute_includes runtime_dependencies, "sqlite3"
    refute_includes runtime_dependencies, "pg"
  end

  private

  # Returns the path to the gem specification under test.
  #
  # @return [String] absolute path to the gem specification
  def gemspec_path
    File.expand_path("../../../../vertiso-authentication.gemspec", __dir__)
  end
end
