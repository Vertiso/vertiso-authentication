# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "omniauth"
require "omniauth-apple"
require "omniauth-github"
require "omniauth-google-oauth2"
require "omniauth/rails_csrf_protection"
require_relative "apple_nonce"
require_relative "developer_strategy"

module Vertiso
  module Authentication
    module Omniauth
      # Builds the host's deferred provider registrations into OmniAuth middleware.
      class Middleware
        # Redacted provider registration failure safe to expose at boot.
        class ProviderConfigurationError < ArgumentError; end

        POSITIONAL_OAUTH2_PROVIDERS = %i[
          apple
          github
          google_oauth2
        ].freeze

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
          AppleNonce.install!
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

          options = registration.options.dup
          if POSITIONAL_OAUTH2_PROVIDERS.include?(registration.name)
            register_oauth2_provider(downstream, registration, options)
          else
            register_custom_provider(downstream, registration, options)
          end
        rescue ProviderConfigurationError
          raise
        rescue StandardError, LoadError
          raise_redacted_configuration_error!(registration)
        end

        # Adds one known OAuth2 provider using its positional credential contract.
        #
        # @param downstream [#call]
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @param options [Hash]
        # @return [#call]
        def register_oauth2_provider(downstream, registration, options)
          validate_oauth2_options!(registration.name, options)
          client_id = options.delete(:client_id)
          client_secret = positional_client_secret(
            registration.name,
            options
          )
          apply_protocol_options!(registration.name, options)

          build_provider(downstream) do |builder|
            builder.provider(
              registration.name,
              client_id,
              client_secret,
              **options
            )
          end
        end

        # Adds an arbitrary strategy through its option hash contract.
        #
        # @param downstream [#call]
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @param options [Hash]
        # @return [#call]
        def register_custom_provider(downstream, registration, options)
          build_provider(downstream) do |builder|
            builder.provider(registration.name, **options)
          end
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

        # Returns the positional secret required by known OAuth2 constructors.
        #
        # Apple generates its real client secret from team, key, and PEM
        # configuration and intentionally receives a blank positional value.
        #
        # @param provider_name [Symbol]
        # @param options [Hash]
        # @return [String]
        def positional_client_secret(provider_name, options)
          return options.delete(:client_secret) unless provider_name == :apple

          options.delete(:client_secret)
          ""
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

        # Validates provider-specific required values without exposing them.
        #
        # @param provider_name [Symbol]
        # @param options [Hash]
        # @return [void]
        # @raise [ProviderConfigurationError]
        def validate_oauth2_options!(provider_name, options)
          required_keys = if provider_name == :apple
                            %i[client_id team_id key_id pem]
                          else
                            %i[client_id client_secret]
                          end
          required_keys.each do |key|
            require_nonblank_provider_option!(
              provider_name,
              options,
              key
            )
          end
        end

        # Applies production protocol behavior without prescribing host secrets.
        #
        # @param name [Symbol]
        # @param options [Hash]
        # @return [void]
        def apply_protocol_options!(name, options)
          case name
          when :google_oauth2
            options[:scope] = "email profile"
          when :apple
            apply_apple_options!(options)
          when :github
            options[:scope] = "user:email"
          end
        end

        # Applies GoalMindr's Apple signing and nonce options.
        #
        # @param options [Hash]
        # @return [void]
        def apply_apple_options!(options)
          options[:scope] = "email name"
          options[:pem] = "#{options[:pem]}\n"
          options[:provider_ignores_state] = true
          options[:nonce_required] = false
          options[:authorize_params] = { nonce: nil }
        end

        # Raises a redacted error when a required provider value is blank.
        #
        # @param provider_name [Symbol]
        # @param options [Hash]
        # @param key [Symbol]
        # @return [void]
        # @raise [ProviderConfigurationError]
        def require_nonblank_provider_option!(
          provider_name,
          options,
          key
        )
          return unless provider_option_blank?(options[key])

          error = ProviderConfigurationError.new(
            "OAuth provider #{provider_name} requires nonblank #{key}"
          )
          raise error, cause: nil
        end

        # Returns whether a provider option is absent, empty, or whitespace.
        #
        # @param value [Object]
        # @return [Boolean]
        def provider_option_blank?(value)
          value.nil? ||
            (value.respond_to?(:empty?) && value.empty?) ||
            (value.is_a?(String) && value.strip.empty?)
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
