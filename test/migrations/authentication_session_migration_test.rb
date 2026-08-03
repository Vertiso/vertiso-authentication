# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationAuthenticationSessionMigrationTest < ActiveSupport::TestCase
  MIGRATION_PATH = Vertiso::Authentication::Engine.root.join("db/migrate")
  MIGRATION_VERSION = 20_260_802_000_000
  TABLE_NAME = :vertiso_authentication_authentication_sessions

  teardown do
    load Rails.root.join("db/schema.rb")
  end

  test "discovers and migrates the authentication session table up and down" do
    context = ActiveRecord::MigrationContext.new([MIGRATION_PATH])

    assert_includes context.migrations.map(&:version), MIGRATION_VERSION

    ActiveRecord::Base.connection.drop_table(TABLE_NAME, if_exists: true)
    context.up(MIGRATION_VERSION)

    assert ActiveRecord::Base.connection.data_source_exists?(TABLE_NAME)

    context.down(0)

    assert_not ActiveRecord::Base.connection.data_source_exists?(TABLE_NAME)
  end
end
