# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    module Auth
      # Composes principal signup and provider entrypoints.
      class SignupFormComponent < ViewComponent::Base
        attr_reader :home_path,
                    :include_developer,
                    :login_path,
                    :oauth_path,
                    :principal,
                    :providers,
                    :registration_path,
                    :theme

        # @param principal [ApplicationRecord] host-owned signup record
        # @param home_path [String] host home destination
        # @param registration_path [String] signup submission destination
        # @param login_path [String] existing-account destination
        # @param providers [Enumerable] provider buttons to render
        # @param oauth_path [#call] provider-name route resolver
        # @param include_developer [Boolean] render the local developer strategy
        # @param theme [Vertiso::Authentication::Theme] semantic presentation
        def initialize(
          principal:,
          home_path:,
          registration_path:,
          login_path:,
          providers:,
          oauth_path:,
          include_developer: false,
          theme: Vertiso::Authentication.configuration.theme
        )
          super()
          @home_path = home_path
          @include_developer = include_developer
          @login_path = login_path
          @oauth_path = oauth_path
          @principal = principal
          @providers = providers
          @registration_path = registration_path
          @theme = theme
        end

        # @return [Object]
        def principal_email
          principal.public_send(
            Vertiso::Authentication.configuration.email_attribute
          )
        end

        # @return [Object]
        def principal_user_name
          principal.public_send(
            Vertiso::Authentication.configuration.user_name_attribute
          )
        end
      end
    end
  end
end
