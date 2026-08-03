# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "securerandom"

module Vertiso
  module Authentication
    module Omniauth
      # Preserves Apple's nonce across its cross-site form-post callback.
      module AppleNonce
        class << self
          # Installs the compatibility behavior once on OmniAuth's Apple strategy.
          #
          # @return [void]
          def install!
            strategy = ::OmniAuth::Strategies::Apple
            strategy.prepend(self) unless strategy.ancestors.include?(self)
          end
        end

        private

        # Creates and stores a nonce in both the session and encrypted cookie.
        #
        # @return [String]
        def new_nonce
          nonce = SecureRandom.urlsafe_base64(16)
          session["omniauth.nonce"] = nonce
          cookies.encrypted[:apple_auth_params] = {
            same_site: :none,
            expires: 1.hour.from_now,
            secure: true,
            value: nonce
          }
          nonce
        end

        # Consumes the callback nonce from the session or encrypted cookie.
        #
        # @return [String, nil]
        def stored_nonce
          nonce = session.delete("omniauth.nonce") ||
                  cookies.encrypted[:apple_auth_params]
          cookies.delete :apple_auth_params
          nonce
        end

        # Returns the Rails cookie jar supplied to the strategy request.
        #
        # @return [ActionDispatch::Cookies::CookieJar]
        def cookies
          request.env["action_dispatch.cookies"]
        end
      end
    end
  end
end
