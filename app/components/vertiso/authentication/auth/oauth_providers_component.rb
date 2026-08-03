# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    module Auth
      # Renders provider entrypoints and optional linked identities.
      class OauthProvidersComponent < ViewComponent::Base
        attr_reader :include_developer,
                    :linked_accounts,
                    :oauth_path,
                    :providers,
                    :theme,
                    :unlink_path

        # @param providers [Enumerable<Vertiso::Authentication::OauthProvider>]
        # @param oauth_path [#call] provider-name route resolver
        # @param linked_accounts [Enumerable, nil] identities to manage
        # @param unlink_path [#call, nil] linked-identity route resolver
        # @param include_developer [Boolean] render the local developer strategy
        # @param theme [Vertiso::Authentication::Theme] semantic presentation
        def initialize(
          providers:,
          oauth_path:,
          linked_accounts: nil,
          unlink_path: nil,
          include_developer: false,
          theme: Vertiso::Authentication.configuration.theme
        )
          super()
          @include_developer = include_developer
          @linked_accounts = linked_accounts
          @oauth_path = oauth_path
          @providers = providers
          @theme = theme
          @unlink_path = unlink_path
        end

        # @param provider [Vertiso::Authentication::OauthProvider]
        # @return [String]
        def provider_label(provider)
          t(
            "vertiso.authentication.components.oauth_providers.continue_with",
            provider: provider.display_name
          )
        end

        # Returns configured providers without duplicating the developer strategy.
        #
        # @return [Enumerable<Vertiso::Authentication::OauthProvider>]
        def displayed_providers
          return providers unless include_developer

          providers.reject do |provider|
            provider.name.to_s == "developer"
          end
        end
      end
    end
  end
end
