# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "generator_test_helper"
require "generators/vertiso/authentication/install_generator"

class VertisoAuthenticationInstallGeneratorTest < Rails::Generators::TestCase
  include VertisoAuthenticationGeneratorTestHelper

  tests Vertiso::Authentication::Generators::InstallGenerator
  destination File.expand_path(
    "../../../../tmp/install_generator",
    __dir__
  )

  setup do
    build_host
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

  private

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
