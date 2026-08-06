# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "open3"

class VertisoAuthenticationEncryptionConfigurationTest < ActiveSupport::TestCase
  teardown do
    ActiveRecord::Encryption.configure(**ACTIVE_RECORD_ENCRYPTION_TEST_KEYS)
  end

  test "skips validation when no OAuth provider is configured" do
    remove_encryption_keys

    assert_nothing_raised do
      Vertiso::Authentication::EncryptionConfiguration.validate!(
        configuration: Vertiso::Authentication::Configuration.new
      )
    end
  end

  test "rejects a configured OAuth provider when encryption keys are missing" do
    configuration = configuration_with_oauth_provider
    remove_encryption_keys

    error = assert_raises ActiveRecord::Encryption::Errors::Configuration do
      Vertiso::Authentication::EncryptionConfiguration.validate!(
        configuration:
      )
    end

    assert_match(/Vertiso Authentication OAuth providers require working/i,
                 error.message)
    assert_match(/Active Record Encryption guide/i, error.message)
    assert_not_includes error.message, "configured-client-secret"
  end

  test "accepts configured OAuth providers when encryption round trips" do
    assert_nothing_raised do
      Vertiso::Authentication::EncryptionConfiguration.validate!(
        configuration: configuration_with_oauth_provider
      )
    end
  end

  test "fails host boot when configured OAuth providers lack encryption keys" do
    stdout, stderr, status = Open3.capture3(
      {
        "RAILS_ENV" => "test",
        "VAUTH_TEST_CONFIGURE_OAUTH" => "1"
      },
      Gem.ruby,
      "-I#{repository_root.join('lib')}",
      "-e",
      'require "./test/dummy_standard/config/environment"',
      chdir: repository_root
    )

    refute status.success?, stdout
    assert_match(/Vertiso Authentication OAuth providers require working/i,
                 stderr)
  end

  private

  # Returns configuration with one provider whose application secret must not
  # be resolved by encryption validation.
  #
  # @return [Vertiso::Authentication::Configuration]
  def configuration_with_oauth_provider
    Vertiso::Authentication::Configuration.new.tap do |configuration|
      configuration.oauth_provider(
        :custom,
        strategy: :custom,
        arguments: [
          "configured-client-id",
          -> { "configured-client-secret" }
        ]
      )
    end
  end

  # Removes Rails' default encryption credentials and resets its context.
  #
  # @return [void]
  def remove_encryption_keys
    ActiveRecord::Encryption.configure(
      primary_key: nil,
      deterministic_key: nil,
      key_derivation_salt: nil
    )
  end

  # Returns the standalone gem repository root.
  #
  # @return [Pathname]
  def repository_root
    Pathname.new(File.expand_path("../../../..", __dir__))
  end
end
