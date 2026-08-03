# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "rack/mock"
require "rack/session/cookie"
require "rack/test"
require "uri"

class VertisoAuthenticationDeveloperOauthCallbackTest < ActiveSupport::TestCase
  PASSWORD = "TestPassword1234!"

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "developer one-click follows the ordinary linked-account login path" do
    principal = User.create!(
      email: "developer@example.com",
      user_name: "developer",
      email_verified_at: Time.current,
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
    provider = Vertiso::Authentication::OauthProvider.create!(
      name: "developer",
      display_name: "Developer",
      trusts_email: true
    )
    account = principal.authentication_oauth_accounts.create!(
      oauth_provider: provider,
      provider_uid: "developer-#{principal.id}",
      user_credentials: {
        "token" => "stale-token"
      }
    )
    configuration = developer_configuration(principal:)

    with_rails_environment("development") do
      rack_session = Rack::Test::Session.new(
        Rack::MockSession.new(developer_stack(configuration:))
      )

      rack_session.post("/auth/developer")

      assert_equal 302, rack_session.last_response.status
      assert_equal(
        "/auth/developer/callback",
        URI(rack_session.last_response.location).path
      )

      rack_session.follow_redirect!

      assert_equal 302, rack_session.last_response.status
      assert_equal(
        "/signed-in?principal_id=#{principal.id}&source=oauth",
        relative_location(rack_session.last_response.location)
      )

      rack_session.get("/authentication-state")

      state = JSON.parse(rack_session.last_response.body)

      assert_equal principal.id, state.fetch("principal_id")
      assert_predicate state.fetch("remember_token"), :present?
      assert_equal Time.current.to_i, account.reload.last_used_at.to_i
      assert_equal({}, account.user_credentials)
      assert_equal 1,
                   principal.authentication_oauth_accounts.where(
                     oauth_provider: provider,
                     provider_uid: "developer-#{principal.id}"
                   ).count
    end
  end

  private

  # Builds a development provider configuration around the seeded principal.
  #
  # @param principal [User]
  # @return [Vertiso::Authentication::Configuration]
  def developer_configuration(principal:)
    configuration = Vertiso::Authentication.configuration
    configuration.post_authentication_destination =
      lambda do |controller, authenticated_principal|
        controller.main_app.signed_in_path(
          principal_id: authenticated_principal.id,
          source: "oauth"
        )
      end
    configuration.oauth_provider(
      :developer,
      principal_resolver: -> { User.find_by(id: principal.id) }
    )
    configuration
  end

  # Builds the real developer middleware in front of the dummy host.
  #
  # @param configuration [Vertiso::Authentication::Configuration]
  # @return [Rack::Session::Cookie]
  def developer_stack(configuration:)
    middleware = Vertiso::Authentication::Omniauth::Middleware.new(
      Rails.application,
      configuration:
    )
    Rack::Session::Cookie.new(
      middleware,
      secret: "developer-oauth-integration-session-secret-" * 2
    )
  end

  # Temporarily applies the exact Rails environment gate.
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

  # Returns a redirect location without scheme and host.
  #
  # @param location [String]
  # @return [String]
  def relative_location(location)
    uri = URI(location)
    uri.query ? "#{uri.path}?#{uri.query}" : uri.path
  end
end
