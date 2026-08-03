# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

ActiveRecord::Schema[8.1].define do
  create_table :users, force: true do |table|
    table.string :email, null: false
    table.string :name, null: false
    table.string :password_digest
    table.datetime :email_verified_at
    table.timestamps
  end

  add_index :users, :email, unique: true
end
