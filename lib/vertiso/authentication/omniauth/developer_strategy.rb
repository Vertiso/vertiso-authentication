# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "omniauth"

module Vertiso
  module Authentication
    module Omniauth
      # Development-only OmniAuth strategy for an existing seeded principal.
      class DeveloperStrategy
        include ::OmniAuth::Strategy

        SESSION_KEY = "vertiso.authentication.developer_requested".freeze

        option :name, "developer"
        option :principal_resolver
        option :authentication_configuration

        uid do
          "developer-#{developer_principal.id}"
        end

        info do
          {
            name: developer_user_name,
            email: developer_email,
            nickname: developer_user_name
          }
        end

        credentials do
          {}
        end

        extra do
          {
            raw_info: {
              "id" => "developer-#{developer_principal.id}",
              "email" => developer_email,
              "login" => developer_user_name
            }
          }
        end

        # Starts a one-click flow and redirects to the ordinary callback path.
        #
        # @return [Array]
        def request_phase
          return fail!(:developer_unavailable) unless development?
          return fail!(:developer_resolver_missing) unless principal_resolver
          return fail!(:developer_principal_missing) unless resolve_principal

          session[SESSION_KEY] = true
          redirect callback_path
        end

        # Resolves the principal again and emits a normal OmniAuth auth hash.
        #
        # @return [Array]
        def callback_phase
          return fail!(:developer_unavailable) unless development?
          return fail!(:developer_request_missing) unless session.delete(SESSION_KEY)
          return fail!(:developer_resolver_missing) unless principal_resolver
          return fail!(:developer_principal_missing) unless resolve_principal

          super
        end

        private

        attr_reader :developer_principal

        # Returns whether execution is within the Rails development environment.
        #
        # @return [Boolean]
        def development?
          Rails.env.development?
        end

        # Returns the configured request-time principal resolver.
        #
        # @return [Object, #call, nil]
        def principal_resolver
          options.principal_resolver
        end

        # Resolves and validates an existing persisted principal.
        #
        # @return [Object, nil]
        def resolve_principal
          principal = if principal_resolver.respond_to?(:call)
                        principal_resolver.call
                      else
                        principal_resolver
                      end
          return unless principal&.persisted?

          @developer_principal = principal
        end

        # Returns the host authentication configuration.
        #
        # @return [Vertiso::Authentication::Configuration]
        def authentication_configuration
          options.authentication_configuration
        end

        # Returns the principal's configured email identity.
        #
        # @return [String]
        def developer_email
          developer_principal.public_send(
            authentication_configuration.email_attribute
          ).to_s
        end

        # Returns the principal's configured user-name identity.
        #
        # @return [String]
        def developer_user_name
          developer_principal.public_send(
            authentication_configuration.user_name_attribute
          ).to_s
        end
      end
    end
  end
end
