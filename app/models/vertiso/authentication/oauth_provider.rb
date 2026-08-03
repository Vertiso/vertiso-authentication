# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # An external identity provider configured for authentication.
    class OauthProvider < ::ApplicationRecord
      has_many :user_oauth_accounts, dependent: :destroy

      validates :name, presence: true, uniqueness: true
      validates :display_name, presence: true

      # Returns whether the callback email has the provider's required trust signal.
      #
      # @param auth [OmniAuth::AuthHash, nil]
      # @return [Boolean]
      def email_trusted_for?(auth)
        return false if auth&.info&.email.blank?
        return true if trusts_email

        case name
        when "github" then github_verified_primary_email?(auth)
        else false
        end
      end

      private

      # Returns whether GitHub corroborates the callback email as verified and primary.
      #
      # @param auth [OmniAuth::AuthHash]
      # @return [Boolean]
      def github_verified_primary_email?(auth)
        email = auth.info.email.to_s.downcase
        return false if email.blank?

        all_emails = auth.extra&.all_emails
        return false if all_emails.blank?

        all_emails.any? do |entry|
          entry["email"].to_s.downcase == email &&
            entry["verified"] == true &&
            entry["primary"] == true
        end
      end
    end
  end
end
