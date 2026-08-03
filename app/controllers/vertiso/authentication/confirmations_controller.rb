# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Consumes anonymous email-verification tokens and resends confirmation mail.
    class ConfirmationsController < ::ApplicationController
      include DispatchHandling

      before_action :require_confirmation_principal, only: :create

      rate_limit to: 10,
                 within: 1.hour,
                 by: -> { current_principal.id },
                 with: -> { render_resend_rate_limited },
                 name: "vertiso-authentication-confirmation-resend-per-hour",
                 only: :create

      # Confirms the principal identified by the signed token.
      #
      # @return [void]
      def show
        principal = principal_class.find_by_token_for(
          :email_verification,
          params[:token]
        )

        if principal.nil?
          redirect_to invalid_confirmation_destination,
                      alert: t("vertiso.authentication.confirmations.invalid_link")
          return
        end

        if principal.email_verified?
          redirect_to confirmation_destination(principal),
                      notice: t("vertiso.authentication.confirmations.already_confirmed")
          return
        end

        if principal.update(email_confirmation_attribute => Time.current)
          redirect_to confirmation_destination(principal),
                      notice: t("vertiso.authentication.confirmations.confirmed")
        else
          redirect_to confirmation_required_destination(principal),
                      alert: principal.errors.full_messages.to_sentence
        end
      end

      # Resends confirmation mail to the authenticated principal.
      #
      # @return [void]
      def create
        if current_principal.email_verified?
          redirect_to main_app.root_path,
                      notice: t("vertiso.authentication.confirmations.already_confirmed")
          return
        end

        dispatched = safely_dispatch(label: "Resend") do
          AuthenticationMailer.confirm(current_principal).deliver_later
        end

        if dispatched
          redirect_to confirmation_required_destination(current_principal),
                      notice: t("vertiso.authentication.confirmations.resent")
        else
          redirect_to confirmation_required_destination(current_principal),
                      alert: t("vertiso.authentication.confirmations.dispatch_failed")
        end
      end

      private

      # @return [Class]
      def principal_class
        authentication_configuration.principal_class
      end

      # @return [Symbol]
      def email_confirmation_attribute
        authentication_configuration.email_confirmed_at_attribute
      end

      # @return [void]
      def require_confirmation_principal
        return if authenticated?

        redirect_to login_path, status: :see_other
      end

      # @return [String]
      def invalid_confirmation_destination
        authenticated? ? main_app.root_path : login_path
      end

      # @param principal [ApplicationRecord]
      # @return [String]
      def confirmation_destination(principal)
        return login_path unless authenticated?
        return main_app.root_path unless current_principal == principal

        configured_destination(
          authentication_configuration.post_confirmation_destination,
          principal,
          fallback: main_app.root_path
        )
      end

      # @param principal [ApplicationRecord]
      # @return [String]
      def confirmation_required_destination(principal)
        configured_destination(
          authentication_configuration.confirmation_required_destination,
          principal,
          fallback: main_app.root_path
        )
      end

      # @param callable [Proc, nil]
      # @param principal [ApplicationRecord]
      # @param fallback [String]
      # @return [String]
      def configured_destination(callable, principal, fallback:)
        return callable.call(self, principal) if callable

        fallback
      end

      # @return [void]
      def render_resend_rate_limited
        redirect_to confirmation_required_destination(current_principal),
                    alert: t("vertiso.authentication.confirmations.rate_limited"),
                    status: :see_other
      end

      # @return [Vertiso::Authentication::Configuration]
      def authentication_configuration
        Vertiso::Authentication.configuration
      end
    end
  end
end
