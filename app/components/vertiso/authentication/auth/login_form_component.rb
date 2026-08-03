# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    module Auth
      # Composes password and provider login into the authentication shell.
      class LoginFormComponent < ViewComponent::Base
        attr_reader :errors,
                    :forgot_password_path,
                    :home_path,
                    :include_developer,
                    :login,
                    :oauth_path,
                    :providers,
                    :registration_path,
                    :session_path,
                    :theme

        # @param login [String, nil] prefilled email or user name
        # @param home_path [String] host home destination
        # @param session_path [String] password-login destination
        # @param forgot_password_path [String] reset request destination
        # @param registration_path [String] signup destination
        # @param providers [Enumerable] provider buttons to render
        # @param oauth_path [#call] provider-name route resolver
        # @param errors [Enumerable<String>] errors to summarize
        # @param include_developer [Boolean] render the local developer strategy
        # @param theme [Vertiso::Authentication::Theme] semantic presentation
        def initialize(
          session_path:,
          forgot_password_path:,
          registration_path:,
          providers:,
          oauth_path:,
          home_path:,
          login: nil,
          errors: [],
          include_developer: false,
          theme: Vertiso::Authentication.configuration.theme
        )
          super()
          @errors = errors
          @forgot_password_path = forgot_password_path
          @home_path = home_path
          @include_developer = include_developer
          @login = login
          @oauth_path = oauth_path
          @providers = providers
          @registration_path = registration_path
          @session_path = session_path
          @theme = theme
        end
      end
    end
  end
end
