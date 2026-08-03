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

          builder = ::OmniAuth::Builder.new
          configuration.oauth_providers.each do |registration|
            if registration.name == :developer
              register_developer(builder, registration)
            else
              register_provider(builder, registration)
            end
          end
          builder.run(downstream)
          builder.to_app
        end

        # Adds one resolved provider strategy to the OmniAuth builder.
        #
        # @param builder [OmniAuth::Builder]
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [void]
        def register_provider(builder, registration)
          options = registration.options.dup
          client_id = options.delete(:client_id)
          client_secret = options.delete(:client_secret)
          apply_protocol_options!(registration.name, options)

          builder.provider(
            registration.name,
            client_id,
            client_secret,
            **options
          )
        end

        # Adds the developer strategy only in Rails development.
        #
        # @param builder [OmniAuth::Builder]
        # @param registration [Vertiso::Authentication::ProviderRegistration]
        # @return [void]
        def register_developer(builder, registration)
          return unless Rails.env.development?

          builder.provider(
            DeveloperStrategy,
            principal_resolver: registration.value_resolver(
              :principal_resolver
            ),
            authentication_configuration: configuration
          )
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
          %i[team_id key_id pem].each do |key|
            require_provider_option!(:apple, options, key)
          end

          options[:scope] = "email name"
          options[:pem] = "#{options[:pem]}\n"
          options[:provider_ignores_state] = true
          options[:nonce_required] = false
          options[:authorize_params] = { nonce: nil }
        end

        # Raises when provider signing configuration is absent.
        #
        # @param provider_name [Symbol]
        # @param options [Hash]
        # @param key [Symbol]
        # @return [void]
        # @raise [ArgumentError]
        def require_provider_option!(provider_name, options, key)
          return if options.key?(key) && !options[key].nil?

          raise ArgumentError,
                "OAuth provider #{provider_name} requires #{key}"
        end
      end
    end
  end
end
