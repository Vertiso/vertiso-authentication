# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

ActiveRecord::Schema[8.1].define do
  create_table :users, force: true do |table|
    table.string :email, null: false
    table.string :user_name, null: false
    table.string :password_digest
    table.string :session_token_seed, default: '', null: false
    table.datetime :email_verified_at
    table.timestamps
  end

  add_index :users, :email, unique: true
  add_index :users, :user_name, unique: true

  create_table :vertiso_authentication_authentication_sessions, force: true do |table|
    table.references :principal,
                     polymorphic: true,
                     index: { name: "index_authentication_sessions_on_principal" }
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
