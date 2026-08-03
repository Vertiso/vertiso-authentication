# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "rack/mock"
require "rack/session/cookie"

module OmniAuth
  module Strategies
    # Real non-OAuth2 strategy with one declared argument and option values.
    class TaskEightOneArgument
      include OmniAuth::Strategy

      args [:client_id]
      option :name, "task_eight_one_argument"
      option :client_secret
      option :api_token
    end

    # Real non-OAuth2 strategy that rejects its resolved configuration.
    class TaskEightExploding
      include OmniAuth::Strategy

      option :name, "task_eight_exploding"
      option :api_token

      # Raises an error containing the configured value to test redaction.
      #
      # @param app [#call]
      # @param arguments [Array]
      # @param options [Hash]
      # @raise [ArgumentError]
      def initialize(app, *arguments, **options)
        super
        raise ArgumentError, "rejected #{self.options.api_token}"
      end
    end
  end
end

class VertisoAuthenticationOmniauthMiddlewareTest < ActiveSupport::TestCase
  setup do
    @configuration = Vertiso::Authentication::Configuration.new
    @configuration.oauth_provider(
      :google_oauth2,
      client_id: -> { "google-client-id" },
      client_secret: -> { "google-client-secret" }
    )
    @configuration.oauth_provider(
      :apple,
      client_id: "apple-client-id",
      client_secret: "",
      team_id: "apple-team-id",
      key_id: "apple-key-id",
      pem: "apple-private-key"
    )
    @configuration.oauth_provider(
      :github,
      client_id: "github-client-id",
      client_secret: "github-client-secret"
    )
  end

  test "allows only POST requests to begin authentication" do
    middleware = build_middleware
    session_app = Rack::Session::Cookie.new(
      middleware,
      secret: "test-session-secret-" * 4
    )

    response = Rack::MockRequest.new(session_app).get("/auth/google_oauth2")

    assert_equal %i[post], OmniAuth.config.allowed_request_methods
    assert_equal 404, response.status
    assert_equal "downstream", response.body
  end

  test "builds Google with the production scope and resolved credentials" do
    strategy = strategy_for(build_middleware, :google_oauth2)

    assert_equal "google-client-id", strategy.options.client_id
    assert_equal "google-client-secret", strategy.options.client_secret
    assert_equal "email profile", strategy.options.scope
  end

  test "builds Apple with the production protocol options" do
    strategy = strategy_for(build_middleware, :apple)

    assert_equal "apple-client-id", strategy.options.client_id
    assert_equal "", strategy.options.client_secret
    assert_equal "email name", strategy.options.scope
    assert_equal "apple-team-id", strategy.options.team_id
    assert_equal "apple-key-id", strategy.options.key_id
    assert_equal "apple-private-key\n", strategy.options.pem
    assert_equal true, strategy.options.provider_ignores_state
    assert_equal false, strategy.options.nonce_required
    assert_nil strategy.options.authorize_params.nonce
  end

  test "builds GitHub with the email scope required by provider trust" do
    strategy = strategy_for(build_middleware, :github)

    assert_equal "github-client-id", strategy.options.client_id
    assert_equal "github-client-secret", strategy.options.client_secret
    assert_equal "user:email", strategy.options.scope
  end

  test "preserves the Apple nonce in an encrypted cookie and consumes it on callback" do
    strategy = strategy_for(build_middleware, :apple)
    request = ActionDispatch::TestRequest.create(
      Rails.application.env_config.merge("rack.session" => {})
    )
    cookie_jar = request.cookie_jar
    request.env["action_dispatch.cookies"] = cookie_jar
    strategy.instance_variable_set(:@env, request.env)

    nonce = strategy.send(:new_nonce)

    assert_equal nonce, request.session["omniauth.nonce"]
    assert_equal nonce, cookie_jar.encrypted[:apple_auth_params]

    request.session.delete("omniauth.nonce")

    assert_equal nonce, strategy.send(:stored_nonce)
    assert_nil cookie_jar.encrypted[:apple_auth_params]
  end

  test "fails clearly when Apple signing configuration is absent" do
    configuration = Vertiso::Authentication::Configuration.new
    configuration.oauth_provider(
      :apple,
      client_id: "apple-client-id",
      client_secret: "",
      key_id: "apple-key-id",
      pem: "apple-private-key"
    )

    error = assert_raises ArgumentError do
      build_middleware(configuration:)
    end

    assert_equal(
      "OAuth provider apple requires nonblank team_id",
      error.message
    )
  end

  test "passes arbitrary provider values through a non-OAuth2 strategy option contract" do
    configuration = Vertiso::Authentication::Configuration.new
    secret = "custom-resolved-secret"
    configuration.oauth_provider(
      :task_eight_one_argument,
      client_id: "custom-client-id",
      client_secret: -> { secret },
      api_token: "custom-api-token"
    )

    strategy = strategy_for(
      build_middleware(configuration:),
      :task_eight_one_argument
    )

    assert_equal "custom-client-id", strategy.options.client_id
    assert_equal secret, strategy.options.client_secret
    assert_equal "custom-api-token", strategy.options.api_token
  end

  test "redacts arbitrary strategy construction errors and removes their cause" do
    configuration = Vertiso::Authentication::Configuration.new
    secret = "custom-error-secret"
    configuration.oauth_provider(
      :task_eight_exploding,
      api_token: -> { secret }
    )

    error = assert_raises(
      Vertiso::Authentication::Omniauth::Middleware::ProviderConfigurationError
    ) do
      build_middleware(configuration:)
    end

    assert_includes error.message, "task_eight_exploding"
    assert_includes error.message, "api_token"
    refute_includes error.message, secret
    refute_includes error.full_message, secret
    refute_includes error.inspect, secret
    assert_nil error.cause
  end

  test "requires nonblank Google and GitHub OAuth2 credentials at middleware build" do
    cases = [
      [:google_oauth2, :client_id, nil],
      [:google_oauth2, :client_id, " "],
      [:google_oauth2, :client_secret, nil],
      [:google_oauth2, :client_secret, ""],
      [:github, :client_id, nil],
      [:github, :client_id, " "],
      [:github, :client_secret, nil],
      [:github, :client_secret, ""]
    ]

    cases.each do |provider_name, missing_key, missing_value|
      assert_required_oauth2_value(
        provider_name:,
        missing_key:,
        missing_value:
      )
    end
  end

  test "requires nonblank Apple signing values but permits its blank positional secret" do
    %i[client_id team_id key_id pem].each do |missing_key|
      configuration = apple_configuration(
        missing_key:,
        missing_value: " "
      )

      error = assert_raises(
        Vertiso::Authentication::Omniauth::Middleware::ProviderConfigurationError
      ) do
        build_middleware(configuration:)
      end

      assert_equal(
        "OAuth provider apple requires nonblank #{missing_key}",
        error.message
      )
      assert_nil error.cause
    end

    strategy = strategy_for(
      build_middleware(configuration: apple_configuration),
      :apple
    )

    assert_equal "", strategy.options.client_secret
  end

  private

  # Builds the real Rack middleware around a deterministic downstream app.
  #
  # @param configuration [Vertiso::Authentication::Configuration]
  # @return [Vertiso::Authentication::Omniauth::Middleware]
  def build_middleware(configuration: @configuration)
    downstream = lambda do |_environment|
      [404, { "content-type" => "text/plain" }, ["downstream"]]
    end

    Vertiso::Authentication::Omniauth::Middleware.new(
      downstream,
      configuration:
    )
  end

  # Finds a real OmniAuth strategy instance in the built Rack chain.
  #
  # @param middleware [Vertiso::Authentication::Omniauth::Middleware]
  # @param name [Symbol]
  # @return [OmniAuth::Strategy]
  def strategy_for(middleware, name)
    current = middleware.instance_variable_get(:@app)

    while current.respond_to?(:app)
      return current if current.options.name.to_sym == name

      current = current.app
    end

    flunk "missing #{name} strategy"
  end

  # Asserts a known OAuth2 provider rejects one absent or blank credential.
  #
  # @param provider_name [Symbol]
  # @param missing_key [Symbol]
  # @param missing_value [Object]
  # @return [void]
  def assert_required_oauth2_value(
    provider_name:,
    missing_key:,
    missing_value:
  )
    values = {
      client_id: "#{provider_name}-client-id",
      client_secret: "#{provider_name}-client-secret"
    }
    values[missing_key] = missing_value
    configuration = Vertiso::Authentication::Configuration.new
    configuration.oauth_provider(provider_name, **values)

    error = assert_raises(
      Vertiso::Authentication::Omniauth::Middleware::ProviderConfigurationError
    ) do
      build_middleware(configuration:)
    end

    assert_equal(
      "OAuth provider #{provider_name} requires nonblank #{missing_key}",
      error.message
    )
    assert_nil error.cause
  end

  # Builds an Apple registration with one optionally invalid signing value.
  #
  # @param missing_key [Symbol, nil]
  # @param missing_value [Object]
  # @return [Vertiso::Authentication::Configuration]
  def apple_configuration(missing_key: nil, missing_value: nil)
    values = {
      client_id: "apple-client-id",
      client_secret: "",
      team_id: "apple-team-id",
      key_id: "apple-key-id",
      pem: "apple-private-key"
    }
    values[missing_key] = missing_value if missing_key
    configuration = Vertiso::Authentication::Configuration.new
    configuration.oauth_provider(:apple, **values)
    configuration
  end
end
