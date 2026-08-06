# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "omniauth"
require "omniauth/rails_csrf_protection"
require_relative "developer_strategy"
require_relative "provider_configuration_error"
require_relative "provider_registry"

module Vertiso
  module Authentication
    module Omniauth
      # Builds the host's deferred provider registrations into OmniAuth middleware.
      class Middleware
        ProviderConfigurationError = Omniauth::ProviderConfigurationError

        # Creates the provider middleware around a Rack application.
        #
        # @param app [#call] downstream Rack application
        # @param configuration [Vertiso::Authentication::Configuration]
        def initialize(
          app,
          configuration: Vertiso::Authentication.configuration
        )
          @configuration = configuration
          @app = build_stack(app)
        end

        # Dispatches a request through the configured provider strategies.
        #
        # @param environment [Hash] Rack environment
        # @return [Array]
        def call(environment)
          app.call(environment)
        end

        private

        attr_reader :app, :configuration

        # Builds the real OmniAuth Rack chain and resolves host values once.
        #
        # @param downstream [#call]
        # @return [#call]
        def build_stack(downstream)
          ::OmniAuth.config.allowed_request_methods = %i[post]

          configuration.oauth_providers.reverse_each.reduce(downstream) do |app, registration|
            build_registration(app, registration)
          end
        end

        # Builds one isolated strategy so construction failures identify its provider.
        #
        # @param downstream [#call]
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [#call]
        # @raise [ProviderConfigurationError]
        def build_registration(downstream, registration)
          return register_developer(downstream, registration) if registration.name == :developer

          prepare_known_profile!(registration) if registration.known?
          arguments, options = registration.resolve
          build_provider(downstream) do |builder|
            builder.provider(
              registration.strategy,
              *arguments,
              **options
            )
          end
        rescue ProviderConfigurationError
          raise
        rescue StandardError, LoadError
          raise_redacted_configuration_error!(registration)
        end

        # Loads and installs one selected known provider profile.
        #
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [void]
        # @raise [ProviderConfigurationError]
        def prepare_known_profile!(registration)
          registration.profile.load_strategy!
          registration.profile.install!
        rescue LoadError
          raise_missing_optional_gem!(registration)
        end

        # Builds one real OmniAuth strategy around the downstream Rack app.
        #
        # @param downstream [#call]
        # @yieldparam builder [OmniAuth::Builder]
        # @return [#call]
        def build_provider(downstream)
          builder = ::OmniAuth::Builder.new
          yield builder
          builder.run(downstream)
          builder.to_app
        end

        # Adds the developer strategy only in Rails development.
        #
        # @param downstream [#call]
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [#call]
        def register_developer(downstream, registration)
          return downstream unless Rails.env.development?

          build_provider(downstream) do |builder|
            builder.provider(
              DeveloperStrategy,
              principal_resolver: registration.value_resolver(
                :principal_resolver
              ),
              authentication_configuration: configuration
            )
          end
        end

        # Raises an actionable error for a selected missing strategy gem.
        #
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [void]
        # @raise [ProviderConfigurationError]
        def raise_missing_optional_gem!(registration)
          error = ProviderConfigurationError.new(
            "OAuth provider #{registration.name} requires optional gem " \
            "#{registration.profile.gem_name}"
          )
          raise error, cause: nil
        end

        # Replaces provider construction details with key-only diagnostics.
        #
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [void]
        # @raise [ProviderConfigurationError]
        def raise_redacted_configuration_error!(registration)
          keys = registration.option_keys.map(&:to_s).sort.join(", ")
          message = "OAuth provider #{registration.name} could not be " \
                    "constructed from configured keys: #{keys}"
          raise ProviderConfigurationError.new(message), cause: nil
        end
      end
    end
  end
end
