# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Configures the host application's principal and authentication flows.
    class Configuration
      attr_accessor :principal_class_name,
                    :email_attribute,
                    :user_name_attribute,
                    :email_confirmed_at_attribute,
                    :remember_cookie_key,
                    :remember_token_lifetime,
                    :email_confirmation_lifetime,
                    :password_reset_lifetime,
                    :authentication_session_lifetime,
                    :oauth_principal_attributes,
                    :oauth_user_name_allocator,
                    :confirmation_required_destination,
                    :post_authentication_destination,
                    :post_registration_destination,
                    :post_confirmation_destination,
                    :post_logout_destination,
                    :mailer_sender,
                    :mailer_host,
                    :mailer_url_options,
                    :dispatch_error_reporter

      # Creates configuration using conventional Rails principal defaults.
      #
      # @return [Vertiso::Authentication::Configuration]
      def initialize
        @principal_class_name = "User"
        @email_attribute = :email
        @user_name_attribute = :user_name
        @email_confirmed_at_attribute = :email_verified_at
        @remember_cookie_key = :remember_token
        @remember_token_lifetime = 30.days
        @email_confirmation_lifetime = 24.hours
        @password_reset_lifetime = 1.hour
        @authentication_session_lifetime = 30.days
        @oauth_principal_attributes = ->(auth:) { {} }
        @oauth_user_name_allocator = nil
        @confirmation_required_destination = nil
        @post_authentication_destination = nil
        @post_registration_destination = nil
        @post_confirmation_destination = nil
        @post_logout_destination = nil
        @mailer_sender = nil
        @mailer_host = nil
        @mailer_url_options = {}
        @dispatch_error_reporter = nil
      end

      # Resolves the configured host principal class only when it is used.
      #
      # @return [Class]
      def principal_class
        principal_class_name.constantize
      end
    end
  end
end
