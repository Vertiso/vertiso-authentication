# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Delivers confirmation and recovery messages for configured principals.
    class AuthenticationMailer < ActionMailer::Base
      # Builds an email-verification message with a fresh signed token.
      #
      # @param principal [ApplicationRecord]
      # @return [Mail::Message]
      def confirm(principal)
        @principal = principal
        token = principal.generate_token_for(:email_verification)
        @confirmation_url = confirm_email_url(
          **resolved_url_options,
          token:
        )

        mail(
          from: resolved_configuration_value(configuration.mailer_sender),
          to: principal.public_send(configuration.email_attribute),
          subject: t("vertiso.authentication.mailer.confirmation.subject")
        )
      end

      # Builds a password-reset message from the caller-generated token.
      #
      # @param principal [ApplicationRecord]
      # @param token [String]
      # @return [Mail::Message]
      def reset(principal, token)
        @principal = principal
        @reset_url = reset_password_url(
          **resolved_url_options,
          token:
        )

        mail(
          from: resolved_configuration_value(configuration.mailer_sender),
          to: principal.public_send(configuration.email_attribute),
          subject: t("vertiso.authentication.mailer.password_reset.subject")
        )
      end

      private

      # @return [Hash]
      def resolved_url_options
        options = resolved_configuration_value(configuration.mailer_url_options)
        options = options.to_h.symbolize_keys
        options[:host] = resolved_configuration_value(configuration.mailer_host)
        options
      end

      # @param value [Object, Proc]
      # @return [Object]
      def resolved_configuration_value(value)
        value.respond_to?(:call) ? value.call : value
      end

      # @return [Vertiso::Authentication::Configuration]
      def configuration
        Vertiso::Authentication.configuration
      end
    end
  end
end
