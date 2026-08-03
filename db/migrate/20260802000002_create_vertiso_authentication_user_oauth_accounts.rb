# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

# Creates portable linked external identities for host-owned principals.
class CreateVertisoAuthenticationUserOauthAccounts < ActiveRecord::Migration[8.1]
  PROVIDERS_TABLE = :vertiso_authentication_oauth_providers
  ACCOUNTS_TABLE = :vertiso_authentication_user_oauth_accounts

  # Creates linked accounts and their portable ownership and identity indexes.
  #
  # @return [void]
  def change
    create_table ACCOUNTS_TABLE do |table|
      table.references :principal,
                       polymorphic: true,
                       null: false,
                       index: {
                         name: "idx_vertiso_auth_oauth_accounts_principal"
                       }
      table.references :oauth_provider,
                       null: false,
                       index: {
                         name: "idx_vertiso_auth_oauth_accounts_provider"
                       },
                       foreign_key: {
                         to_table: PROVIDERS_TABLE
                       }
      table.string :provider_uid, null: false
      table.string :email
      table.string :name
      table.json :user_info
      table.json :user_credentials
      table.datetime :last_used_at
      table.timestamps
    end

    add_index ACCOUNTS_TABLE,
              %i[oauth_provider_id provider_uid],
              unique: true,
              name: "idx_vertiso_auth_oauth_accounts_identity"
  end
end
