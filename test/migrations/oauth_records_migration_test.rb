# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationOauthRecordsMigrationTest < ActiveSupport::TestCase
  MIGRATION_PATH = Vertiso::Authentication::Engine.root.join("db/migrate")
  PROVIDERS_TABLE = :vertiso_authentication_oauth_providers
  ACCOUNTS_TABLE = :vertiso_authentication_user_oauth_accounts
  MIGRATION_VERSIONS = [
    20_260_802_000_000,
    20_260_802_000_001,
    20_260_802_000_002
  ].freeze

  teardown do
    load Rails.root.join("db/schema.rb")
  end

  test "discovers and migrates OAuth record tables up and down" do
    context = ActiveRecord::MigrationContext.new([MIGRATION_PATH])

    assert_equal MIGRATION_VERSIONS, context.migrations.map(&:version)

    connection = ActiveRecord::Base.connection
    connection.drop_table(ACCOUNTS_TABLE, if_exists: true)
    connection.drop_table(PROVIDERS_TABLE, if_exists: true)
    connection.drop_table(
      :vertiso_authentication_authentication_sessions,
      if_exists: true
    )

    context.up

    assert connection.data_source_exists?(PROVIDERS_TABLE)
    assert connection.data_source_exists?(ACCOUNTS_TABLE)
    assert_equal :json,
                 connection.columns(ACCOUNTS_TABLE)
                           .index_by(&:name)
                           .fetch("user_info")
                           .type
    assert_equal :json,
                 connection.columns(ACCOUNTS_TABLE)
                           .index_by(&:name)
                           .fetch("user_credentials")
                           .type

    context.down(0)

    assert_not connection.data_source_exists?(ACCOUNTS_TABLE)
    assert_not connection.data_source_exists?(PROVIDERS_TABLE)
  end

  test "uses engine-namespaced portable indexes within the adapter limit" do
    connection = ActiveRecord::Base.connection
    provider_indexes = connection.indexes(PROVIDERS_TABLE)
    account_indexes = connection.indexes(ACCOUNTS_TABLE)
    indexes = provider_indexes + account_indexes

    assert(indexes.all? { |index| index.name.start_with?("idx_vertiso_auth_") })
    assert(
      indexes.all? do |index|
        index.name.length <= connection.index_name_length
      end
    )

    identity = account_indexes.find do |index|
      index.name == "idx_vertiso_auth_oauth_accounts_identity"
    end

    assert_not_nil identity
    assert_predicate identity, :unique
    assert_equal %w[oauth_provider_id provider_uid], identity.columns
  end
end
