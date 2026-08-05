# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "open3"

# Verifies executable README examples and installer capability claims.
class VertisoAuthenticationReadmeTest < ActiveSupport::TestCase
  setup do
    Vertiso::Authentication.reset_configuration!
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "principal configuration example uses the public configuration API" do
    apply_principal_configuration_example

    configuration = Vertiso::Authentication.configuration

    assert_equal "User", configuration.principal_class_name
    assert_equal :email, configuration.email_attribute
    assert_equal :user_name, configuration.user_name_attribute
    assert_equal :email_verified_at,
                 configuration.email_confirmed_at_attribute
  end

  test "installer claims require a host principal and document missing principal failure" do
    assert_match(
      /host application must define its principal model before running the\s+installer/i,
      readme
    )
    assert_match(
      /installer aborts if the configured principal model is missing/i,
      readme
    )
    refute_match(/can generate a minimal one/i, readme)
    refute_match(/generator for applications without one/i, readme)
  end

  test "generic provider example executes through the public initializer API" do
    script = <<~RUBY
      require "vertiso/authentication"
      #{generic_provider_example}
      registration = Vertiso::Authentication.configuration.oauth_providers.find do |provider|
        provider.name == :auth0
      end
      abort "missing auth0" unless registration
      abort "wrong strategy" unless registration.strategy == :auth0
      expected_arguments = ["documented-client-id", "documented-client-secret"]
      abort "wrong arguments" unless registration.arguments == expected_arguments
      abort "wrong scope" unless registration.options[:scope] == "openid email profile"
    RUBY
    stdout, stderr, status = Open3.capture3(
      {
        "AUTH0_CLIENT_ID" => "documented-client-id",
        "AUTH0_CLIENT_SECRET" => "documented-client-secret"
      },
      Gem.ruby,
      "-I#{repository_root.join('lib')}",
      "-e",
      script
    )

    assert status.success?, "#{stdout}\n#{stderr}"
  end

  test "generic provider example requires its optional strategy plugin" do
    assert_match(/gem "omniauth-auth0"/, readme)
    assert_match(/strategy gem must be loaded before middleware construction/i,
                 readme)
  end

  test "legacy credential migration documents a coordinated secure cutover" do
    assert_match(/ordinary rolling deploy is unsafe/i, readme)
    assert_match(/drain every process running the old model/i, readme)
    assert_match(/disable_ddl_transaction!/, readme)
    assert_match(/with_lock/, readme)
    assert_match(/skip.*already encrypted/i, readme)
    assert_match(/backup.*plaintext credentials/i, readme)
    assert_match(/encrypted.*restricted.*retention/i, readme)
  end

  private

  # Applies the documented configuration assignments through the public API.
  #
  # @return [void]
  def apply_principal_configuration_example
    assignments = principal_configuration_example.scan(
      /^\s*config\.(\w+)\s*=\s*(.+)$/
    )
    assert_equal 4, assignments.length

    assignments.each do |attribute, literal|
      Vertiso::Authentication.configuration.public_send(
        "#{attribute}=",
        documented_value(literal)
      )
    end
  end

  # Converts the string and symbol literals accepted by the README contract.
  #
  # @param literal [String]
  # @return [String, Symbol]
  def documented_value(literal)
    symbol_match = /\A:(\w+)\z/.match(literal)
    return symbol_match[1].to_sym if symbol_match

    string_match = /\A"([^"]*)"\z/.match(literal)
    return string_match[1] if string_match

    flunk("Unsupported README configuration value: #{literal}")
  end

  # @return [String]
  def principal_configuration_example
    ruby_examples.find do |example|
      example.include?("Vertiso::Authentication.configure") &&
        !example.include?("oauth_provider")
    end || flunk("README principal configuration example is missing")
  end

  # Returns the executable generic provider example from the README.
  #
  # @return [String]
  def generic_provider_example
    ruby_examples.find do |example|
      example.include?(":auth0") &&
        example.include?("AUTH0_CLIENT_ID")
    end || flunk("README generic provider example is missing")
  end

  # @return [Array<String>]
  def ruby_examples
    readme.scan(/```ruby\n(.*?)```/m).flatten
  end

  # @return [String]
  def readme
    @readme ||= File.read(readme_path)
  end

  # @return [String]
  def readme_path
    File.expand_path("../../../../README.md", __dir__)
  end

  # Returns the standalone gem repository root.
  #
  # @return [Pathname]
  def repository_root
    Pathname.new(File.expand_path("../../../..", __dir__))
  end
end
