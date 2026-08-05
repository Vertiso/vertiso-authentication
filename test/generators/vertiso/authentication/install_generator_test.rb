# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "generator_test_helper"
require "generators/vertiso/authentication/install_generator"
require "open3"

class VertisoAuthenticationInstallGeneratorTest < Rails::Generators::TestCase
  include VertisoAuthenticationGeneratorTestHelper

  self.use_transactional_tests = false

  tests Vertiso::Authentication::Generators::InstallGenerator
  destination File.expand_path(
    "../../../../tmp/install_generator",
    __dir__
  )

  setup do
    ActiveRecord::Base.connection.drop_table(:members, if_exists: true)
    build_host
  end

  teardown do
    ActiveRecord::Base.connection.drop_table(:members, if_exists: true)
  end

  test "installs mapped host integration and portable engine artifacts" do
    run_generator generator_arguments

    assert_file "app/models/member.rb" do |content|
      assert_equal 1, content.scan("include Vertiso::Authentication::Authenticatable").length
    end
    assert_file "config/initializers/vertiso_authentication.rb" do |content|
      assert_includes content, "config.principal_class_name = \"Member\""
      assert_includes content, "config.email_attribute = :contact_email"
      assert_includes content, "config.user_name_attribute = :handle"
      assert_includes content, "config.email_confirmed_at_attribute = :email_confirmed_at"
      assert_includes content, "credentials.dig(:google, :client_id)"
      assert_includes content, "credentials.dig(:apple, :client_id)"
      assert_includes content, "credentials.dig(:github, :client_id)"
      assert_includes content, "strategy: :auth0"
      assert_includes content, 'ENV.fetch("AUTH0_CLIENT_ID")'
      assert_includes content, "Lambdas defer secret lookup until middleware construction"
    end
    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan("mount Vertiso::Authentication::Engine").length
    end
    assert_file "app/assets/tailwind/application.css" do |content|
      assert_equal(
        1,
        content.scan('@import "../builds/tailwind/vertiso_authentication";').length
      )
    end

    migrations = Dir[
      File.join(destination_root, "db/migrate/*.rb")
    ]

    assert_equal 5, migrations.length
    migrations.each do |migration|
      content = File.read(migration)

      assert_nothing_raised do
        RubyVM::InstructionSequence.compile_file(migration)
      end
      refute_includes content, "jsonb"
      refute_includes content, "using:"
      refute_includes content, "where:"
    end
    principal_migration = migrations.find do |migration|
      migration.end_with?("_add_vertiso_authentication_fields_to_members.rb")
    end
    assert principal_migration
    principal_content = File.read(principal_migration)
    assert_includes principal_content, ":password_digest"
    assert_includes principal_content, ":contact_email"
    assert_includes principal_content, ":handle"
    assert_includes principal_content, ":email_confirmed_at"

    session_seed_migration = migrations.find do |migration|
      migration.end_with?("_add_authentication_to_members.rb")
    end
    assert session_seed_migration
    assert_includes File.read(session_seed_migration), ":session_token_seed"

    assert_file "app/components/vertiso/authentication/auth/shell_component.rb"
    assert_file "app/components/vertiso/authentication/auth/shell_component.html.erb"
  end

  test "second installation is idempotent" do
    run_generator generator_arguments
    first_model = File.read(
      File.join(destination_root, "app/models/member.rb")
    )
    first_routes = File.read(
      File.join(destination_root, "config/routes.rb")
    )
    first_tailwind = File.read(
      File.join(destination_root, "app/assets/tailwind/application.css")
    )
    first_migrations = Dir[
      File.join(destination_root, "db/migrate/*.rb")
    ].map { |path| File.basename(path) }.sort

    run_generator generator_arguments

    assert_equal first_model,
                 File.read(File.join(destination_root, "app/models/member.rb"))
    assert_equal first_routes,
                 File.read(File.join(destination_root, "config/routes.rb"))
    assert_equal(
      first_tailwind,
      File.read(
        File.join(destination_root, "app/assets/tailwind/application.css")
      )
    )
    assert_equal(
      first_migrations,
      Dir[
        File.join(destination_root, "db/migrate/*.rb")
      ].map { |path| File.basename(path) }.sort
    )
  end

  test "generated authentication session migration executes with portable index names" do
    run_generator generator_arguments

    assert_generated_migrations_execute(
      "create_vertiso_authentication_authentication_sessions"
    )
  end

  test "generated principal seed migration loads by its filename class" do
    run_generator generator_arguments

    assert_generated_migrations_execute(
      "add_authentication_to_members",
      mode: "principal"
    )
  end

  test "generated fields migration creates portable unique identity indexes" do
    run_generator generator_arguments

    assert_generated_migrations_execute(
      "add_vertiso_authentication_fields_to_members",
      mode: "fields"
    )
  end

  test "generated fields migration preserves existing unique identity indexes" do
    with_existing_principal_identity_columns do
      run_generator generator_arguments

      assert_generated_migrations_execute(
        "add_vertiso_authentication_fields_to_members",
        mode: "preindexed_fields"
      )
    end
  end

  test "all generated migrations execute up and down as one migration set" do
    run_generator generator_arguments

    assert_generated_migrations_execute(
      "create_vertiso_authentication_authentication_sessions",
      "create_vertiso_authentication_oauth_providers",
      "create_vertiso_authentication_user_oauth_accounts",
      "add_authentication_to_members",
      "add_vertiso_authentication_fields_to_members",
      mode: "all"
    )
  end

  private

  def assert_generated_migrations_execute(*suffixes, mode: "empty")
    migration_paths = suffixes.map do |suffix|
      Dir[
        File.join(destination_root, "db/migrate/*_#{suffix}.rb")
      ].fetch(0)
    end
    database_path = File.join(
      destination_root,
      "tmp",
      "#{mode}.sqlite3"
    )
    FileUtils.mkdir_p(File.dirname(database_path))

    stdout, stderr, status = Open3.capture3(
      Gem.ruby,
      "-e",
      generated_migration_runner,
      mode,
      database_path,
      *migration_paths
    )

    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "EXECUTED"
    assert_includes stdout, "ROLLED_BACK" if %w[all preindexed_fields].include?(mode)
  ensure
    FileUtils.rm_f(database_path)
  end

  def generated_migration_runner
    <<~'RUBY'
      require "active_record"

      mode = ARGV.shift
      database_path = ARGV.shift
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: database_path
      )
      connection = ActiveRecord::Base.connection

      if mode == "all"
        connection.create_table(:members)
        connection.execute("INSERT INTO members DEFAULT VALUES")
      elsif mode == "principal"
        connection.create_table(:members) do |table|
          table.string :contact_email
        end
        connection.execute(
          "INSERT INTO members (contact_email) VALUES ('one@example.com')"
        )
      elsif mode.end_with?("fields")
        connection.create_table(:members) do |table|
          if mode == "preindexed_fields"
            table.string :contact_email
            table.string :handle
          end
        end
        if mode == "preindexed_fields"
          connection.add_index(
            :members,
            :contact_email,
            unique: true,
            name: "existing_members_contact_email_unique"
          )
          connection.add_index(
            :members,
            :handle,
            unique: true,
            name: "existing_members_handle_unique"
          )
        end
      end

      migrations = ARGV.map do |path|
        load path
        migration_name = File.basename(path)
                             .sub(/\A\d+_/, "")
                             .delete_suffix(".rb")
                             .camelize
        Object.const_get(migration_name).new
      end
      migrations.each do |migration|
        migration.migrate(:up)
      end

      if mode.end_with?("fields")
        %w[contact_email handle].each do |column|
          indexes = connection.indexes(:members).select do |index|
            index.columns == [column] && index.unique
          end
          raise "missing unique index for #{column}" unless indexes.one?
        end
      end

      puts "EXECUTED"

      if ["all", "preindexed_fields"].include?(mode)
        migrations.reverse_each do |migration|
          migration.migrate(:down)
        end
      end

      if mode == "all"
        engine_tables = %i[
          vertiso_authentication_authentication_sessions
          vertiso_authentication_oauth_providers
          vertiso_authentication_user_oauth_accounts
        ]
        raise "engine tables remain" if engine_tables.any? do |table|
          connection.table_exists?(table)
        end
        raise "principal table removed" unless connection.table_exists?(:members)
        raise "principal rows removed" unless connection.select_value(
          "SELECT COUNT(*) FROM members"
        ) == 1

        puts "ROLLED_BACK"
      elsif mode == "preindexed_fields"
        %w[contact_email handle].each do |column|
          raise "pre-existing column removed: #{column}" unless
            connection.column_exists?(:members, column)
          indexes = connection.indexes(:members).select do |index|
            index.columns == [column] && index.unique
          end
          raise "pre-existing index changed: #{column}" unless
            indexes.map(&:name) == ["existing_members_#{column}_unique"]
        end
        %w[password_digest email_confirmed_at].each do |column|
          raise "generated column remains: #{column}" if
            connection.column_exists?(:members, column)
        end

        puts "ROLLED_BACK"
      end
    RUBY
  end

  def with_existing_principal_identity_columns
    connection = ActiveRecord::Base.connection
    connection.drop_table(:members, if_exists: true)
    connection.create_table(:members) do |table|
      table.string :contact_email
      table.string :handle
    end
    %w[contact_email handle].each do |column|
      connection.add_index(
        :members,
        column,
        unique: true,
        name: "existing_members_#{column}_unique"
      )
    end
    yield
  ensure
    connection&.drop_table(:members, if_exists: true)
  end

  def generator_arguments
    [
      "--principal=Member",
      "--email-attribute=contact_email",
      "--user-name-attribute=handle",
      "--email-confirmed-at-attribute=email_confirmed_at",
      "--views"
    ]
  end
end
