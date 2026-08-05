# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Links a host-owned principal to one external provider identity.
    class UserOauthAccount < ::ApplicationRecord
      belongs_to :principal, polymorphic: true
      belongs_to :oauth_provider

      encrypts :user_credentials

      normalizes :email, with: ->(email) { email.strip.downcase }

      validates :provider_uid, presence: true
      validates :provider_uid,
                uniqueness: {
                  scope: :oauth_provider_id
                }
    end
  end
end
