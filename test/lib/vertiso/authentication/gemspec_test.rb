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

  test "keeps concrete OmniAuth strategies optional for host applications" do
    specification = Gem::Specification.load(gemspec_path)
    development_dependencies = specification.development_dependencies.map(&:name)
    runtime_dependencies = specification.runtime_dependencies.map(&:name)
    provider_gems = %w[
      omniauth-apple
      omniauth-github
      omniauth-google-oauth2
    ]

    provider_gems.each do |name|
      assert_includes development_dependencies, name
      refute_includes runtime_dependencies, name
    end
    assert_includes runtime_dependencies, "omniauth"
    assert_includes runtime_dependencies, "omniauth-rails_csrf_protection"
  end

  test "preserves the patched OAuth2 security floor" do
    specification = Gem::Specification.load(gemspec_path)
    dependency = specification.runtime_dependencies.find do |candidate|
      candidate.name == "oauth2"
    end

    assert dependency
    assert dependency.requirement.satisfied_by?(Gem::Version.new("2.0.22"))
    refute dependency.requirement.satisfied_by?(Gem::Version.new("2.0.21"))
  end

  private

  # Returns the path to the gem specification under test.
  #
  # @return [String] absolute path to the gem specification
  def gemspec_path
    File.expand_path("../../../../vertiso-authentication.gemspec", __dir__)
  end
end
