# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "apple_nonce"
require_relative "developer_strategy"
require_relative "provider_profile"

module Vertiso
  module Authentication
    module Omniauth
      # Canonical construction profiles for production-supported providers.
      class ProviderRegistry
        PROFILES = {
          apple: ProviderProfile.new(
            name: :apple,
            strategy: :apple,
            gem_name: "omniauth-apple",
            require_path: "omniauth-apple",
            required_keys: %i[client_id team_id key_id pem],
            arguments: ->(values) { [values.fetch(:client_id), ""] },
            options: lambda { |values|
              values.except(:client_id, :client_secret).merge(
                scope: "email name",
                pem: normalize_pem(values.fetch(:pem)),
                provider_ignores_state: true,
                nonce_required: false,
                authorize_params: { nonce: nil }
              )
            },
            setup: -> { AppleNonce.install! }
          ),
          developer: ProviderProfile.new(
            name: :developer,
            strategy: DeveloperStrategy
          ),
          github: ProviderProfile.new(
            name: :github,
            strategy: :github,
            gem_name: "omniauth-github",
            require_path: "omniauth-github",
            required_keys: %i[client_id client_secret],
            arguments: lambda { |values|
              [values.fetch(:client_id), values.fetch(:client_secret)]
            },
            options: lambda { |values|
              values.except(:client_id, :client_secret).merge(
                scope: merge_scopes(
                  required: "user:email",
                  configured: values[:scope],
                  separator: ","
                )
              )
            }
          ),
          google_oauth2: ProviderProfile.new(
            name: :google_oauth2,
            strategy: :google_oauth2,
            gem_name: "omniauth-google-oauth2",
            require_path: "omniauth-google-oauth2",
            required_keys: %i[client_id client_secret],
            arguments: lambda { |values|
              [values.fetch(:client_id), values.fetch(:client_secret)]
            },
            options: lambda { |values|
              values.except(:client_id, :client_secret).merge(
                scope: merge_scopes(
                  required: "email profile",
                  configured: values[:scope],
                  separator: " "
                )
              )
            }
          )
        }.freeze

        class << self
          # Returns a known provider profile.
          #
          # @param name [String, Symbol]
          # @return [ProviderProfile, nil]
          def fetch(name)
            PROFILES[name.to_sym]
          end

          # Returns whether the provider has a known construction profile.
          #
          # @param name [String, Symbol]
          # @return [Boolean]
          def known?(name)
            PROFILES.key?(name.to_sym)
          end

          # Returns every known provider key.
          #
          # @return [Array<Symbol>]
          def names
            PROFILES.keys
          end

          private

          # Adds host scopes without removing required provider identity scopes.
          #
          # @param required [String]
          # @param configured [String, Array<String>, nil]
          # @param separator [String]
          # @return [String]
          def merge_scopes(required:, configured:, separator:)
            required_scopes = required.split(/[\s,]+/)
            configured_scopes = Array(configured).flat_map do |value|
              value.to_s.split(/[\s,]+/)
            end
            (required_scopes + configured_scopes).reject(&:empty?).uniq.join(
              separator
            )
          end

          # Normalizes Apple's signing key to exactly one trailing newline.
          #
          # @param value [Object]
          # @return [String]
          def normalize_pem(value)
            "#{value.to_s.sub(/\n+\z/, '')}\n"
          end
        end
      end
    end
  end
end
