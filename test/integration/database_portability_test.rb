# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "generators/vertiso/authentication/install_generator"
require "tmpdir"

# Proves the generated schema and engine record behavior on the selected adapter.
class DatabasePortabilityTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  ENGINE_TABLES = %i[
    vertiso_authentication_user_oauth_accounts
    vertiso_authentication_oauth_providers
    vertiso_authentication_authentication_sessions
  ].freeze

  GENERATED_MIGRATION_SUFFIXES = %w[
    create_vertiso_authentication_authentication_sessions
    create_vertiso_authentication_oauth_providers
    create_vertiso_authentication_user_oauth_accounts
    add_authentication_to_members
    add_vertiso_authentication_fields_to_members
  ].freeze

  setup do
    reset_database!
    configure_portability_principal
    generate_installer_migrations
  end

  teardown do
    rollback_generated_migrations
    remove_generated_migration_constants
    restore_dummy_schema
    Vertiso::Authentication.reset_configuration!
  end

  test "generated migrations and engine records are portable" do
    migrate_generated_schema_up

    assert_equal 5, @migrations.length
    assert_seeded_existing_principal
    principal = create_normalized_principal
    provider = create_provider
    assert_json_round_trips(principal:, provider:)
    assert_database_identity_uniqueness(principal:, provider:)
    assert_authentication_session_state(principal:)

    migrate_generated_schema_down
    assert_generated_schema_rolled_back
  end

  private

  # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  def connection
    ActiveRecord::Base.connection
  end

  # @return [void]
  def reset_database!
    ENGINE_TABLES.each do |table|
      connection.drop_table(table, if_exists: true)
    end
    connection.drop_table(:members, if_exists: true)
    connection.create_table(:members) do |table|
      table.string :contact_email
    end
    connection.add_index(
      :members,
      :contact_email,
      unique: true,
      name: "existing_members_contact_email_unique"
    )
    connection.execute(
      "INSERT INTO members (contact_email) VALUES ('existing@example.com')"
    )
  end

  # @return [void]
  def configure_portability_principal
    Vertiso::Authentication.reset_configuration!
    Vertiso::Authentication.configure do |config|
      config.principal_class_name = "PortabilityPrincipal"
      config.email_attribute = :contact_email
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end
  end

  # @return [void]
  def generate_installer_migrations
    @destination_root = Dir.mktmpdir("vertiso-authentication-portability")
    write_host_skeleton
    generator = Vertiso::Authentication::Generators::InstallGenerator.new(
      [],
      generator_options,
      destination_root: @destination_root
    )
    generator.invoke_all
    @migration_paths = GENERATED_MIGRATION_SUFFIXES.map do |suffix|
      Dir[File.join(@destination_root, "db/migrate/*_#{suffix}.rb")].fetch(0)
    end
  end

  # @return [void]
  def write_host_skeleton
    write_host_file(
      "app/models/member.rb",
      "class Member < ApplicationRecord\nend\n"
    )
    write_host_file(
      "config/routes.rb",
      "Rails.application.routes.draw do\nend\n"
    )
    write_host_file(
      "app/assets/tailwind/application.css",
      "@import \"tailwindcss\";\n"
    )
  end

  # @param path [String]
  # @param content [String]
  # @return [void]
  def write_host_file(path, content)
    destination = File.join(@destination_root, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, content)
  end

  # @return [Hash<Symbol, Object>]
  def generator_options
    {
      principal: "Member",
      email_attribute: "contact_email",
      user_name_attribute: "handle",
      email_confirmed_at_attribute: "email_confirmed_at"
    }
  end

  # @return [void]
  def migrate_generated_schema_up
    @migrations = @migration_paths.map do |path|
      constant_name = migration_class_name(path)
      preserve_existing_migration_constant(constant_name)
      load path
      Object.const_get(constant_name).new
    end
    with_quiet_migrations do
      @migrations.each { |migration| migration.migrate(:up) }
    end
    PortabilityPrincipal.reset_column_information
    reset_engine_model_columns
  end

  # @return [void]
  def migrate_generated_schema_down
    with_quiet_migrations do
      @migrations.reverse_each { |migration| migration.migrate(:down) }
    end
    @migrated_down = true
  end

  # @return [void]
  def rollback_generated_migrations
    return if @migrations.blank? || @migrated_down

    with_quiet_migrations do
      @migrations.reverse_each do |migration|
        migration.migrate(:down)
      rescue ActiveRecord::StatementInvalid
        nil
      end
    end
  end

  # @yield Runs migrations with logging disabled.
  # @return [void]
  def with_quiet_migrations
    previous = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    yield
  ensure
    ActiveRecord::Migration.verbose = previous
  end

  # @param path [String]
  # @return [String]
  def migration_class_name(path)
    File.basename(path)
        .sub(/\A\d+_/, "")
        .delete_suffix(".rb")
        .camelize
  end

  # @return [void]
  def reset_engine_model_columns
    Vertiso::Authentication::AuthenticationSession.reset_column_information
    Vertiso::Authentication::OauthProvider.reset_column_information
    Vertiso::Authentication::UserOauthAccount.reset_column_information
  end

  # @return [void]
  def assert_seeded_existing_principal
    seed = connection.select_value(
      "SELECT session_token_seed FROM members ORDER BY id LIMIT 1"
    )

    assert_predicate seed, :present?
  end

  # @return [PortabilityPrincipal]
  def create_normalized_principal
    principal = PortabilityPrincipal.create!(
      contact_email: " Person@Example.com ",
      handle: " Person ",
      password: "TestPassword1234!"
    )

    assert_equal "person@example.com", principal.contact_email
    assert_equal "person", principal.handle
    assert_equal principal,
                 PortabilityPrincipal.find_email(email: " PERSON@EXAMPLE.COM ")
    assert_equal principal, PortabilityPrincipal.find_login(" PERSON ")
    principal
  end

  # @return [Vertiso::Authentication::OauthProvider]
  def create_provider
    Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true,
      configuration: { "scope" => ["email", "profile"] }
    )
  end

  # @param principal [PortabilityPrincipal]
  # @param provider [Vertiso::Authentication::OauthProvider]
  # @return [void]
  def assert_json_round_trips(principal:, provider:)
    account = Vertiso::Authentication::UserOauthAccount.create!(
      principal:,
      oauth_provider: provider,
      provider_uid: "provider-uid",
      email: "oauth@example.com",
      user_info: {
        "image" => "https://example.test/avatar.png",
        "roles" => ["reader", "author"]
      },
      user_credentials: {
        "token" => "provider-token",
        "expires" => true,
        "metadata" => { "region" => "us-west" }
      }
    )
    session = Vertiso::Authentication::AuthenticationSession.create!(
      principal:,
      session_identifier: "json-session",
      data: {
        "return_to" => "/settings",
        "flags" => ["trusted", "remembered"]
      }
    )

    assert_equal ["reader", "author"], account.reload.user_info.fetch("roles")
    assert_equal "us-west",
                 account.user_credentials.dig("metadata", "region")
    assert_equal ["trusted", "remembered"],
                 session.reload.data.fetch("flags")
    assert_equal ["email", "profile"],
                 provider.reload.configuration.fetch("scope")
  end

  # @param principal [PortabilityPrincipal]
  # @param provider [Vertiso::Authentication::OauthProvider]
  # @return [void]
  def assert_database_identity_uniqueness(principal:, provider:)
    assert_raises(ActiveRecord::RecordNotUnique) do
      PortabilityPrincipal.new(
        contact_email: principal.contact_email,
        handle: "different-handle"
      ).save!(validate: false)
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      PortabilityPrincipal.new(
        contact_email: "different@example.com",
        handle: principal.handle
      ).save!(validate: false)
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      Vertiso::Authentication::UserOauthAccount.new(
        principal:,
        oauth_provider: provider,
        provider_uid: "provider-uid"
      ).save!(validate: false)
    end
  end

  # @param principal [PortabilityPrincipal]
  # @return [void]
  def assert_authentication_session_state(principal:)
    now = Time.zone.parse("2026-08-03 12:00:00")
    active = Vertiso::Authentication::AuthenticationSession.create!(
      principal:,
      session_identifier: "active-session",
      expires_at: now + 1.hour
    )
    indefinite = Vertiso::Authentication::AuthenticationSession.create!(
      principal:,
      session_identifier: "indefinite-session"
    )
    inactive = Vertiso::Authentication::AuthenticationSession.create!(
      principal:,
      session_identifier: "inactive-session",
      expires_at: now
    )

    assert active.active_at?(now)
    assert indefinite.active_at?(now)
    refute inactive.active_at?(now)
    json_session = Vertiso::Authentication::AuthenticationSession.find_by!(
      session_identifier: "json-session"
    )
    assert_equal [json_session.id, active.id, indefinite.id].sort,
                 Vertiso::Authentication::AuthenticationSession
                   .active_at(now)
                   .pluck(:id)
                   .sort
    assert_equal [inactive.id],
                 Vertiso::Authentication::AuthenticationSession
                   .inactive_at(now)
                   .pluck(:id)
  end

  # @return [void]
  def assert_generated_schema_rolled_back
    ENGINE_TABLES.each do |table|
      refute connection.table_exists?(table)
    end
    assert connection.table_exists?(:members)
    assert_equal 2, connection.select_value("SELECT COUNT(*) FROM members")
    refute connection.column_exists?(:members, :session_token_seed)
    assert connection.column_exists?(:members, :contact_email)
    assert_equal ["existing@example.com", "person@example.com"],
                 connection.select_values(
                   "SELECT contact_email FROM members ORDER BY id"
                 )
    preserved_indexes = connection.indexes(:members).select do |index|
      index.columns == ["contact_email"] && index.unique
    end
    assert_equal ["existing_members_contact_email_unique"],
                 preserved_indexes.map(&:name)
    refute connection.column_exists?(:members, :password_digest)
    refute connection.column_exists?(:members, :handle)
    refute connection.column_exists?(:members, :email_confirmed_at)
  end

  # @return [void]
  def remove_generated_migration_constants
    Array(@migration_paths).each do |path|
      constant_name = migration_class_name(path)
      Object.send(:remove_const, constant_name) if Object.const_defined?(constant_name)
    end
    (@replaced_migration_constants || {}).each do |name, constant|
      Object.const_set(name, constant)
    end
  end

  # @param name [String]
  # @return [void]
  def preserve_existing_migration_constant(name)
    return unless Object.const_defined?(name, false)

    @replaced_migration_constants ||= {}
    @replaced_migration_constants[name] = Object.const_get(name)
    Object.send(:remove_const, name)
  end

  # @return [void]
  def restore_dummy_schema
    FileUtils.remove_entry(@destination_root) if @destination_root && File.exist?(@destination_root)
    connection.drop_table(:members, if_exists: true)
    load Rails.root.join("db/schema.rb")
  end
end

# Host-owned principal used only by the adapter portability contract.
class PortabilityPrincipal < ApplicationRecord
  self.table_name = "members"

  include Vertiso::Authentication::Authenticatable
end
