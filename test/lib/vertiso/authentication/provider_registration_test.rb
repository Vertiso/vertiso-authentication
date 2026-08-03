# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationProviderRegistrationTest < ActiveSupport::TestCase
  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "resolves provider values from host callables only when options are requested" do
    resolution_count = 0
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :google_oauth2,
      client_id: lambda {
        resolution_count += 1
        "client-id"
      },
      client_secret: -> { "client-secret" }
    )

    assert_equal 0, resolution_count
    resolved_options = registration.options

    assert_equal "client-id", resolved_options.fetch(:client_id)
    assert_equal "client-secret",
                 resolved_options.fetch(:client_secret)
    assert_equal 1, resolution_count
  end

  test "accepts literal provider values and arbitrary strategy options" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :future_provider,
      client_id: "client-id",
      client_secret: "client-secret",
      tenant: "tenant-id",
      prompt: "select_account"
    )

    assert_equal(
      {
        client_id: "client-id",
        client_secret: "client-secret",
        tenant: "tenant-id",
        prompt: "select_account"
      },
      registration.options
    )
  end

  test "leaves known-provider validation to middleware construction" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :google_oauth2,
      client_secret: "client-secret"
    )
    second_registration = Vertiso::Authentication::ProviderRegistration.new(
      :github,
      client_id: "client-id"
    )

    assert_equal(
      { client_secret: "client-secret" },
      registration.options
    )
    assert_equal(
      { client_id: "client-id" },
      second_registration.options
    )
  end

  test "does not persist or inspect resolved provider secrets" do
    secret = "resolved-secret-value"
    provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      configuration: {
        button_label: "Continue with Google"
      },
      trusts_email: true
    )
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :google_oauth2,
      client_id: "client-id",
      client_secret: -> { secret }
    )

    assert_equal secret, registration.options.fetch(:client_secret)

    provider.reload

    refute_includes provider.attributes.inspect, secret
    refute_includes provider.inspect, secret
    refute_includes registration.inspect, secret
  end

  test "registers provider resolvers through host configuration" do
    registration = Vertiso::Authentication.configuration.oauth_provider(
      :github,
      client_id: "client-id",
      client_secret: "client-secret",
      scope: "user:email"
    )

    assert_same registration,
                Vertiso::Authentication.configuration.oauth_providers.fetch(0)
    assert_equal :github, registration.name
    assert_equal "user:email", registration.options.fetch(:scope)
  end

  test "replaces a provider registration with the same strategy name" do
    configuration = Vertiso::Authentication.configuration
    configuration.oauth_provider(
      :github,
      client_id: "first-id",
      client_secret: "first-secret"
    )
    replacement = configuration.oauth_provider(
      :github,
      client_id: "second-id",
      client_secret: "second-secret"
    )

    assert_equal [replacement], configuration.oauth_providers
    assert_equal "second-id", replacement.options.fetch(:client_id)
  end
end
