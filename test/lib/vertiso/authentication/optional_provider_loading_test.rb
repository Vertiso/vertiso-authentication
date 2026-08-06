# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "open3"
require "tmpdir"

class VertisoAuthenticationOptionalProviderLoadingTest < ActiveSupport::TestCase
  test "loading the engine does not load concrete provider strategies" do
    script = <<~'RUBY'
      require "vertiso/authentication"

      concrete = $LOADED_FEATURES.grep(
        /omniauth-(?:apple|github|google-oauth2)/
      )
      abort concrete.join("\n") unless concrete.empty?
    RUBY
    stdout, stderr, status = Open3.capture3(
      Gem.ruby,
      "-I#{repository_root.join('lib')}",
      "-e",
      script
    )

    assert status.success?, "#{stdout}\n#{stderr}"
  end

  test "a provider-free host bundle resolves and boots the packaged runtime" do
    Dir.mktmpdir("vertiso-authentication-provider-free") do |directory|
      gemfile = File.join(directory, "Gemfile")
      File.write(
        gemfile,
        <<~GEMFILE
          source "https://rubygems.org"
          gem "vertiso-authentication", path: #{repository_root.to_s.inspect}
        GEMFILE
      )
      environment = {
        "BUNDLE_GEMFILE" => gemfile,
        "BUNDLE_IGNORE_CONFIG" => "1"
      }

      assert_bundle_command(environment, directory, "lock", "--local")
      lockfile_path = File.join(directory, "Gemfile.lock")
      assert File.file?(lockfile_path)
      lockfile = File.read(lockfile_path)
      provider_gems.each do |name|
        refute_match(/^    #{Regexp.escape(name)} /, lockfile)
      end

      script = <<~RUBY
        require "vertiso/authentication"
        provider_gems = %w[
          omniauth-apple
          omniauth-github
          omniauth-google-oauth2
        ]
        loaded = provider_gems.select { |name| Gem.loaded_specs.key?(name) }
        abort loaded.join(", ") unless loaded.empty?
      RUBY
      assert_bundle_command(
        environment,
        directory,
        "exec",
        Gem.ruby,
        "-e",
        script
      )
    end
  end

  private

  # Returns the standalone gem repository root.
  #
  # @return [Pathname]
  def repository_root
    Pathname.new(File.expand_path("../../../..", __dir__))
  end

  # Runs Bundler inside the isolated host definition.
  #
  # @param environment [Hash]
  # @param directory [String]
  # Additional positional arguments are forwarded to Bundler.
  # @return [void]
  def assert_bundle_command(environment, directory, *)
    stdout = nil
    stderr = nil
    status = nil
    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(
        environment.merge(
          "BUNDLE_APP_CONFIG" => File.join(directory, ".bundle")
        ),
        "bundle",
        *,
        chdir: directory
      )
    end

    assert status.success?, "#{stdout}\n#{stderr}"
  end

  # Returns concrete provider plugins that must remain absent from core hosts.
  #
  # @return [Array<String>]
  def provider_gems
    %w[
      omniauth-apple
      omniauth-github
      omniauth-google-oauth2
    ]
  end
end
