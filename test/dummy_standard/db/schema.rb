# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

ActiveRecord::Schema[8.1].define do
  create_table :users, force: true do |table|
    table.string :email, null: false
    table.string :user_name, null: false
    table.string :name
    table.string :password_digest
    table.string :session_token_seed, default: '', null: false
    table.datetime :email_verified_at
    table.timestamps
  end

  add_index :users, :email, unique: true
  add_index :users, :user_name, unique: true

  create_table :vertiso_authentication_oauth_providers, force: true do |table|
    table.string :name, null: false
    table.string :display_name, null: false
    table.boolean :active, default: true, null: false
    table.json :configuration, default: {}, null: false
    table.boolean :trusts_email, default: false, null: false
    table.timestamps
  end

  add_index :vertiso_authentication_oauth_providers,
            :name,
            unique: true,
            name: "idx_vertiso_auth_oauth_providers_name"

  create_table :vertiso_authentication_user_oauth_accounts, force: true do |table|
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
                       to_table: :vertiso_authentication_oauth_providers
                     }
    table.string :provider_uid, null: false
    table.string :email
    table.string :name
    table.json :user_info
    table.json :user_credentials
    table.datetime :last_used_at
    table.timestamps
  end

  add_index :vertiso_authentication_user_oauth_accounts,
            %i[oauth_provider_id provider_uid],
            unique: true,
            name: "idx_vertiso_auth_oauth_accounts_identity"

  create_table :vertiso_authentication_authentication_sessions, force: true do |table|
    table.references :principal,
                     polymorphic: true,
                     index: { name: "index_vertiso_auth_sessions_on_principal" }
    table.string :session_identifier
    table.json :data, default: {}, null: false
    table.string :ip_address
    table.string :user_agent
    table.datetime :last_activity_at
    table.datetime :expires_at
  end

  add_index :vertiso_authentication_authentication_sessions,
            :session_identifier,
            unique: true
  add_index :vertiso_authentication_authentication_sessions, :last_activity_at
  add_index :vertiso_authentication_authentication_sessions, :expires_at
end
