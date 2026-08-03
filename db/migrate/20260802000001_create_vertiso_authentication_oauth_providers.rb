# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

# Creates the portable external identity provider catalog.
class CreateVertisoAuthenticationOauthProviders < ActiveRecord::Migration[8.1]
  PROVIDERS_TABLE = :vertiso_authentication_oauth_providers

  # Creates the provider catalog and its unique configured-name index.
  #
  # @return [void]
  def change
    create_table PROVIDERS_TABLE do |table|
      table.string :name, null: false
      table.string :display_name, null: false
      table.boolean :active, default: true, null: false
      table.json :configuration, default: {}, null: false
      table.boolean :trusts_email, default: false, null: false
      table.timestamps
    end

    add_index PROVIDERS_TABLE,
              :name,
              unique: true,
              name: "idx_vertiso_auth_oauth_providers_name"
  end
end
