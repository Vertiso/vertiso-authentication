# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Handles password-backed browser login and logout.
    class SessionsController < ::ApplicationController
      # Renders the password login form.
      #
      # @return [void]
      def new
        redirect_to authentication_destination(current_principal) if authenticated?
      end

      # Authenticates configured principal credentials.
      #
      # @return [void]
      def create
        credentials = params.expect(session: %i[login password])
        principal = authentication_configuration.principal_class.authenticate(
          credentials[:login].to_s.strip,
          credentials[:password].to_s
        )

        if principal
          complete_login(principal:)
        else
          flash.now[:alert] = t("vertiso.authentication.sessions.invalid_credentials")
          render :new, status: :unprocessable_content
        end
      end

      # Logs out the current principal.
      #
      # @return [void]
      def destroy
        principal = current_principal
        log_out
        redirect_to logout_destination(principal),
                    status: :see_other,
                    notice: t("vertiso.authentication.sessions.signed_out")
      end

      private

      # @param principal [ApplicationRecord]
      # @return [void]
      def complete_login(principal:)
        log_in(principal:)
        destination = recall_location || authentication_destination(principal)
        redirect_to destination,
                    notice: t("vertiso.authentication.sessions.signed_in")
      end

      # @param principal [ApplicationRecord, nil]
      # @return [String]
      def authentication_destination(principal)
        configured_destination(
          authentication_configuration.post_authentication_destination,
          principal
        )
      end

      # @param principal [ApplicationRecord, nil]
      # @return [String]
      def logout_destination(principal)
        configured_destination(
          authentication_configuration.post_logout_destination,
          principal
        )
      end

      # @param callable [Proc, nil]
      # @param principal [ApplicationRecord, nil]
      # @return [String]
      def configured_destination(callable, principal)
        return callable.call(self, principal) if callable

        main_app.root_path
      end

      # @return [Vertiso::Authentication::Configuration]
      def authentication_configuration
        Vertiso::Authentication.configuration
      end
    end
  end
end
