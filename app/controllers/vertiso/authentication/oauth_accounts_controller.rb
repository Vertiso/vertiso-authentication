# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Removes external identities through the authenticated principal scope.
    class OauthAccountsController < ::ApplicationController
      before_action :require_authenticated_principal

      # Unlinks one external identity owned by the current principal.
      #
      # @return [void]
      def destroy
        account = current_principal.authentication_oauth_accounts.find_by(
          id: params[:id]
        )

        if account&.destroy
          redirect_to oauth_accounts_destination,
                      notice: t(
                        "vertiso.authentication.oauth_accounts.unlinked",
                        provider: account.oauth_provider.display_name
                      )
        else
          redirect_to oauth_accounts_destination,
                      alert: t(
                        "vertiso.authentication.oauth_accounts.unlink_failed"
                      )
        end
      end

      private

      # Requires an authenticated principal without exposing account existence.
      #
      # @return [void]
      def require_authenticated_principal
        return if authenticated?

        redirect_to login_path
      end

      # Returns the host destination after linked-account management.
      #
      # @return [String]
      def oauth_accounts_destination
        callable = Vertiso::Authentication.configuration
                                          .post_authentication_destination
        return callable.call(self, current_principal) if callable

        main_app.root_path
      end
    end
  end
end
