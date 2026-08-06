# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationProviderRegistryTest < ActiveSupport::TestCase
  test "catalogs the production provider profiles" do
    assert_equal %i[apple developer github google_oauth2], registry.names.sort
  end

  test "builds Google's positional credentials and required identity scope" do
    profile = registry.fetch(:google_oauth2)

    assert_equal :google_oauth2, profile.strategy
    assert_equal "omniauth-google-oauth2", profile.gem_name
    assert_equal "omniauth-google-oauth2", profile.require_path
    assert_equal %i[client_id client_secret], profile.required_keys
    assert_equal ["client-id", "client-secret"], profile.arguments_for(
      client_id: "client-id",
      client_secret: "client-secret"
    )
    assert_equal "email profile", profile.options_for({}).fetch(:scope)
  end

  test "adds Google API scopes without removing required identity scopes" do
    options = registry.fetch(:google_oauth2).options_for(
      scope: "calendar.readonly,email"
    )

    assert_equal "email profile calendar.readonly", options.fetch(:scope)
  end

  test "builds Apple's production positional and protocol configuration" do
    profile = registry.fetch(:apple)
    values = {
      client_id: "apple-client-id",
      team_id: "apple-team-id",
      key_id: "apple-key-id",
      pem: "apple-private-key"
    }

    assert_equal %i[client_id team_id key_id pem], profile.required_keys
    assert_equal ["apple-client-id", ""], profile.arguments_for(values)
    assert_equal(
      {
        scope: "email name",
        team_id: "apple-team-id",
        key_id: "apple-key-id",
        pem: "apple-private-key\n",
        provider_ignores_state: true,
        nonce_required: false,
        authorize_params: { nonce: nil }
      },
      profile.options_for(values)
    )
  end

  test "does not duplicate Apple's PEM newline" do
    profile = registry.fetch(:apple)

    options = profile.options_for(
      client_id: "apple-client-id",
      team_id: "apple-team-id",
      key_id: "apple-key-id",
      pem: "apple-private-key\n"
    )

    assert_equal "apple-private-key\n", options.fetch(:pem)
  end

  test "builds GitHub's positional credentials and verified-email scope" do
    profile = registry.fetch(:github)

    assert_equal :github, profile.strategy
    assert_equal "omniauth-github", profile.gem_name
    assert_equal %i[client_id client_secret], profile.required_keys
    assert_equal ["client-id", "client-secret"], profile.arguments_for(
      client_id: "client-id",
      client_secret: "client-secret"
    )
    assert_equal "user:email", profile.options_for({}).fetch(:scope)
  end

  test "adds GitHub API scopes without removing verified-email access" do
    options = registry.fetch(:github).options_for(
      scope: "repo,gist,user:email"
    )

    assert_equal "user:email,repo,gist", options.fetch(:scope)
  end

  test "catalogs the engine-owned developer strategy without an optional gem" do
    profile = registry.fetch(:developer)

    assert_equal Vertiso::Authentication::Omniauth::DeveloperStrategy,
                 profile.strategy
    assert_nil profile.gem_name
    assert_nil profile.require_path
    assert_empty profile.required_keys
  end

  test "returns no profile for an unknown provider" do
    assert_nil registry.fetch(:auth0)
    refute registry.known?(:auth0)
  end

  test "protects global profiles from host mutation" do
    profile = registry.fetch(:google_oauth2)
    options = profile.options_for(prompt: "select_account")
    options[:scope] = "changed"

    assert profile.frozen?
    assert profile.required_keys.frozen?
    assert_equal "email profile", profile.options_for({}).fetch(:scope)
  end

  test "copies and freezes mutable profile metadata" do
    gem_name = +"omniauth-custom"
    require_path = +"omniauth-custom"
    strategy = +"custom"
    profile = Vertiso::Authentication::Omniauth::ProviderProfile.new(
      name: :custom,
      strategy:,
      gem_name:,
      require_path:
    )

    gem_name.replace("changed-gem")
    require_path.replace("changed-path")
    strategy.replace("changed-strategy")

    assert_equal "omniauth-custom", profile.gem_name
    assert_equal "omniauth-custom", profile.require_path
    assert_equal "custom", profile.strategy
    assert profile.gem_name.frozen?
    assert profile.require_path.frozen?
    assert profile.strategy.frozen?
  end

  private

  # Returns the provider registry after producing an assertion failure when
  # the production registry has not been implemented yet.
  #
  # @return [Vertiso::Authentication::Omniauth::ProviderRegistry]
  def registry
    registry_name = "Vertiso::Authentication::Omniauth::ProviderRegistry"
    assert Object.const_defined?(registry_name), "#{registry_name} is missing"

    Object.const_get(registry_name)
  end
end
