# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationProviderRegistrationTest < ActiveSupport::TestCase
  class GenericStrategy
    include OmniAuth::Strategy

    option :name, "generic_strategy"
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "resolves known provider values only when construction is requested" do
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
    arguments, options = registration.resolve

    assert_equal ["client-id", "client-secret"], arguments
    assert_equal "email profile", options.fetch(:scope)
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
        prompt: "select_account",
        name: "future_provider"
      },
      registration.options
    )
  end

  test "registers generic positional arguments and keyword options" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :auth0,
      strategy: :auth0,
      arguments: [
        -> { "client-id" },
        -> { "client-secret" }
      ],
      options: {
        scope: "openid email profile",
        tenant: -> { "tenant-id" }
      }
    )

    assert_equal :auth0, registration.name
    assert_equal :auth0, registration.strategy
    assert_equal ["client-id", "client-secret"], registration.arguments
    assert_equal "openid email profile", registration.options.fetch(:scope)
    assert_equal "tenant-id", registration.options.fetch(:tenant)
    assert_equal "auth0", registration.options.fetch(:name)
    refute registration.known?
  end

  test "accepts a strategy class for a generic provider key" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :enterprise_login,
      strategy: GenericStrategy,
      options: { prompt: "login" }
    )

    assert_equal GenericStrategy, registration.strategy
    assert_equal "enterprise_login", registration.options.fetch(:name)
  end

  test "defaults an unknown provider strategy to its provider key" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :future_provider,
      api_token: "token"
    )

    assert_equal :future_provider, registration.strategy
    assert_equal "token", registration.options.fetch(:api_token)
    assert_equal "future_provider", registration.options.fetch(:name)
  end

  test "resolves nested deferred values once per construction snapshot" do
    resolution_count = 0
    resolver = lambda do
      resolution_count += 1
      "resolved-secret"
    end
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :nested_provider,
      arguments: [resolver],
      options: {
        nested: {
          credential: resolver
        }
      }
    )

    assert_equal 0, resolution_count
    first = registration.resolve
    second = registration.resolve

    assert_equal [["resolved-secret"], {
      nested: { credential: "resolved-secret" },
      name: "nested_provider"
    }], first
    assert_equal first, second
    refute_same first, second
    assert_equal 4, resolution_count
  end

  test "does not freeze mutable objects owned by the host" do
    arguments = ["literal-argument"]
    literal = "literal-option"
    resolved = "resolved-option"
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :custom,
      arguments:,
      options: {
        literal:,
        resolved: -> { resolved }
      }
    )

    snapshot = registration.resolve

    refute arguments.frozen?
    refute arguments.fetch(0).frozen?
    refute literal.frozen?
    refute resolved.frozen?
    assert snapshot.frozen?
    assert snapshot.fetch(0).frozen?
    assert snapshot.fetch(0).fetch(0).frozen?
    assert snapshot.fetch(1).frozen?
    refute_same arguments.fetch(0), snapshot.fetch(0).fetch(0)
    refute_same literal, snapshot.fetch(1).fetch(:literal)
    refute_same resolved, snapshot.fetch(1).fetch(:resolved)
  end

  test "uses a known profile without exposing provider construction in the host" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :github,
      client_id: -> { "github-id" },
      client_secret: -> { "github-secret" }
    )

    assert registration.known?
    assert_equal :github, registration.strategy
    assert_equal ["github-id", "github-secret"], registration.arguments
    assert_equal "user:email", registration.options.fetch(:scope)
  end

  test "rejects a strategy override that would bypass a known profile" do
    error = assert_raises(
      Vertiso::Authentication::Omniauth::ProviderConfigurationError
    ) do
      Vertiso::Authentication::ProviderRegistration.new(
        :github,
        strategy: :github,
        client_id: "secret-id",
        client_secret: "secret-value"
      )
    end

    assert_equal(
      "OAuth provider github uses its registered provider profile and does " \
      "not accept a strategy override",
      error.message
    )
    refute_includes error.full_message, "secret-id"
    refute_includes error.full_message, "secret-value"
    assert_nil error.cause
  end

  test "rejects positional arguments that a known profile would ignore" do
    error = assert_raises(
      Vertiso::Authentication::Omniauth::ProviderConfigurationError
    ) do
      Vertiso::Authentication::ProviderRegistration.new(
        :github,
        arguments: ["ignored-id", "ignored-secret"],
        client_id: "configured-id",
        client_secret: "configured-secret"
      )
    end

    assert_equal(
      "OAuth provider github uses its registered provider profile and does " \
      "not accept positional arguments",
      error.message
    )
    refute_includes error.full_message, "ignored-secret"
    assert_nil error.cause
  end

  test "merges generic legacy keywords with explicit options" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :custom,
      api_token: "legacy-token",
      options: {
        api_token: "explicit-token",
        scope: "profile"
      }
    )

    assert_equal "explicit-token", registration.options.fetch(:api_token)
    assert_equal "profile", registration.options.fetch(:scope)
  end

  test "sorts mixed string and symbol diagnostic keys without resolving values" do
    registration = Vertiso::Authentication::ProviderRegistration.new(
      :custom,
      api_token: "legacy-token",
      options: {
        "tenant" => "tenant-id"
      }
    )

    assert_equal [:api_token, "tenant"], registration.configured_keys
    assert_includes registration.inspect,
                    'configured_keys=[:api_token, "tenant"]'
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

    assert_equal [:client_secret], registration.configured_keys
    assert_equal [:client_id], second_registration.configured_keys
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

    assert_equal secret, registration.arguments.fetch(1)

    provider.reload

    refute_includes provider.attributes.inspect, secret
    refute_includes provider.inspect, secret
    refute_includes registration.inspect, secret
    refute_includes registration.inspect, "resolved-secret-value"
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
    assert_equal "second-id", replacement.arguments.fetch(0)
  end
end
