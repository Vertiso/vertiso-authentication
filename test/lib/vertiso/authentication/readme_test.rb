# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

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
end
