# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "rubygems/package"
require "tmpdir"

# Verifies the actual gem archive contains only public runtime/package files.
class VertisoAuthenticationPackageTest < ActiveSupport::TestCase
  DOCUMENTATION_FILES = %w[
    CHANGELOG.md
    LICENSE
    README.md
    SECURITY.md
  ].freeze

  RUNTIME_DIRECTORIES = %w[
    app
    config
    db/migrate
    lib
  ].freeze

  test "built gem contains the complete public package and no internal artifacts" do
    expected = expected_package_files
    contents = built_gem_contents

    assert_equal expected, contents
    refute(contents.any? { |path| path.start_with?("test/") })
    refute(contents.any? { |path| path.start_with?("docs/internal/") })
    refute(contents.any? { |path| path.start_with?(".superpowers/") })
    refute(contents.any? { |path| path.start_with?("tmp/", "pkg/") })
    refute(contents.any? { |path| File.basename(path).start_with?(".env") })
    refute(contents.any? { |path| path.end_with?(".key") })
  end

  private

  # @return [Array<String>]
  def expected_package_files
    runtime_files = RUNTIME_DIRECTORIES.flat_map do |directory|
      Dir[File.join(repository_root, directory, "**", "*")]
    end
    (runtime_files.select { |path| File.file?(path) }.map do |path|
      path.delete_prefix("#{repository_root}/")
    end + DOCUMENTATION_FILES).sort
  end

  # @return [Array<String>]
  def built_gem_contents
    configured_path = ENV.fetch("PACKAGE_PATH", nil)
    return Gem::Package.new(configured_path).contents.sort if configured_path.present?

    specification = Gem::Specification.load(
      File.join(repository_root, "vertiso-authentication.gemspec")
    )

    Dir.mktmpdir("vertiso-authentication-package") do |directory|
      package_path = File.join(directory, "#{specification.full_name}.gem")
      Gem::Package.build(specification, true, false, package_path)
      return Gem::Package.new(package_path).contents.sort
    end
  end

  # @return [String]
  def repository_root
    @repository_root ||= File.expand_path("../../../..", __dir__)
  end
end
