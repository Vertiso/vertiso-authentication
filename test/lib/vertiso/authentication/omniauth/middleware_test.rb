# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "rack/mock"
require "rack/session/cookie"

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

    assert_equal "OAuth provider apple requires team_id", error.message
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
end
