# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "logger"
require "rack/mock"
require "rack/session/cookie"
require "stringio"
require "uri"

class VertisoAuthenticationOmniauthDeveloperStrategyTest < ActiveSupport::TestCase
  setup do
    @configuration = Vertiso::Authentication::Configuration.new
    @original_logger = OmniAuth.config.logger
    @log_output = StringIO.new
    OmniAuth.config.logger = Logger.new(@log_output)
  end

  teardown do
    OmniAuth.config.logger = @original_logger
  end

  test "does not register or resolve the developer strategy outside development" do
    resolution_count = 0
    @configuration.oauth_provider(
      :developer,
      principal_resolver: lambda {
        resolution_count += 1
        confirmed_principal
      }
    )

    with_rails_environment("production") do
      middleware = build_middleware
      response = session_request(middleware).post("/auth/developer")

      assert_nil strategy_for(middleware, :developer)
      assert_equal 404, response.status
      assert_equal 0, resolution_count
    end
  end

  test "one click sends a stable auth hash through the ordinary callback" do
    password = "TestPassword1234!"
    principal = confirmed_principal(password:)
    @configuration.oauth_provider(
      :developer,
      principal_resolver: -> { User.find_by(id: principal.id) }
    )

    with_rails_environment("development") do
      middleware = build_middleware
      start_response, callback_response = perform_developer_flow(middleware)
      auth = @callback_auth

      assert_equal 302, start_response.status
      assert_equal "/auth/developer/callback",
                   URI(start_response.location).path
      assert_equal 200, callback_response.status
      assert_instance_of OmniAuth::AuthHash, auth
      assert_equal "developer", auth.provider
      assert_equal "developer-#{principal.id}", auth.uid
      assert_equal principal.email, auth.info.email
      assert_equal principal.user_name, auth.info.nickname
      assert_equal principal.user_name, auth.info.name
      assert_equal(
        {
          "id" => "developer-#{principal.id}",
          "email" => principal.email,
          "login" => principal.user_name
        },
        auth.extra.raw_info.to_h
      )
      refute_includes start_response.body, password
      refute_includes callback_response.body, password
      refute_includes @log_output.string, password
    end
  end

  test "fails closed when the principal resolver is missing" do
    @configuration.oauth_provider(:developer)
    principal_count = User.count

    with_rails_environment("development") do
      response = session_request(build_middleware).post("/auth/developer")

      assert_equal 302, response.status
      assert_includes response.location, "developer_resolver_missing"
      assert_equal principal_count, User.count
      assert_nil @callback_auth
    end
  end

  test "fails closed when the configured principal is missing" do
    @configuration.oauth_provider(
      :developer,
      principal_resolver: -> { User.find_by(email: "missing@example.com") }
    )
    principal_count = User.count

    with_rails_environment("development") do
      response = session_request(build_middleware).post("/auth/developer")

      assert_equal 302, response.status
      assert_includes response.location, "developer_principal_missing"
      assert_equal principal_count, User.count
      assert_nil @callback_auth
    end
  end

  test "fails closed when the resolver returns a persisted object of the wrong class" do
    wrong_record = Vertiso::Authentication::OauthProvider.create!(
      name: "developer",
      display_name: "Developer"
    )
    @configuration.oauth_provider(
      :developer,
      principal_resolver: -> { wrong_record }
    )
    principal_count = User.count

    with_rails_environment("development") do
      response = session_request(build_middleware).post("/auth/developer")

      assert_equal 302, response.status
      assert_includes response.location, "developer_principal_missing"
      assert_equal principal_count, User.count
      assert_nil @callback_auth
    end
  end

  test "fails closed when the resolver returns an unsaved principal" do
    @configuration.oauth_provider(
      :developer,
      principal_resolver: lambda {
        User.new(
          email: "unsaved@example.com",
          user_name: "unsaved"
        )
      }
    )
    principal_count = User.count

    with_rails_environment("development") do
      response = session_request(build_middleware).post("/auth/developer")

      assert_equal 302, response.status
      assert_includes response.location, "developer_principal_missing"
      assert_equal principal_count, User.count
      assert_nil @callback_auth
    end
  end

  test "refuses to execute a previously built developer strategy outside development" do
    @configuration.oauth_provider(
      :developer,
      principal_resolver: -> { confirmed_principal }
    )
    middleware = with_rails_environment("development") do
      build_middleware
    end

    with_rails_environment("test") do
      response = session_request(middleware).post("/auth/developer")

      assert_equal 302, response.status
      assert_includes response.location, "developer_unavailable"
      assert_nil @callback_auth
    end
  end

  private

  # Builds middleware with a callback endpoint that captures the real auth hash.
  #
  # @return [Vertiso::Authentication::Omniauth::Middleware]
  def build_middleware
    downstream = lambda do |environment|
      @callback_auth = environment["omniauth.auth"]
      status = @callback_auth ? 200 : 404
      [status, { "content-type" => "text/plain" }, [@callback_auth.inspect]]
    end

    Vertiso::Authentication::Omniauth::Middleware.new(
      downstream,
      configuration: @configuration
    )
  end

  # Wraps middleware in the Rack session required by OmniAuth.
  #
  # @param middleware [#call]
  # @return [Rack::MockRequest]
  def session_request(middleware)
    session_app = Rack::Session::Cookie.new(
      middleware,
      secret: "test-session-secret-" * 4
    )
    Rack::MockRequest.new(session_app)
  end

  # Performs the request and callback phases with the same session cookie.
  #
  # @param middleware [#call]
  # @return [Array<Rack::MockResponse>]
  def perform_developer_flow(middleware)
    request = session_request(middleware)
    start_response = request.post("/auth/developer")
    session_cookie = start_response["set-cookie"].split(";").first
    callback_path = URI(start_response.location).path
    callback_response = request.get(
      callback_path,
      "HTTP_COOKIE" => session_cookie
    )

    [start_response, callback_response]
  end

  # Finds a real OmniAuth strategy instance in the built Rack chain.
  #
  # @param middleware [Vertiso::Authentication::Omniauth::Middleware]
  # @param name [Symbol]
  # @return [OmniAuth::Strategy, nil]
  def strategy_for(middleware, name)
    current = middleware.instance_variable_get(:@app)

    while current.respond_to?(:app)
      return current if current.options.name.to_sym == name

      current = current.app
    end

    nil
  end

  # Runs a block with an exact Rails environment inquiry.
  #
  # @param name [String]
  # @yieldreturn [Object]
  # @return [Object]
  def with_rails_environment(name, &)
    environment = ActiveSupport::EnvironmentInquirer.new(name)
    environment_was_defined = Rails.instance_variable_defined?(:@_env)
    original_environment = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(:@_env, environment)
    yield
  ensure
    if environment_was_defined
      Rails.instance_variable_set(:@_env, original_environment)
    else
      Rails.remove_instance_variable(:@_env)
    end
  end

  # Creates a persisted principal without exposing its password to the strategy.
  #
  # @param password [String]
  # @return [User]
  def confirmed_principal(password: "TestPassword1234!")
    @confirmed_principal ||= User.create!(
      email: "developer@example.com",
      user_name: "developer",
      email_verified_at: Time.current,
      password:,
      password_confirmation: password
    )
  end
end
