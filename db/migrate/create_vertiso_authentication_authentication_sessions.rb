# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

# Creates portable database-backed metadata for authentication sessions.
class CreateVertisoAuthenticationAuthenticationSessions < ActiveRecord::Migration[8.1]
  # Creates the authentication-session metadata table and its lookup indexes.
  #
  # @return [void]
  def change
    create_table :vertiso_authentication_authentication_sessions do |table|
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
end
