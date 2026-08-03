# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require 'test_helper'
require 'erb'

class AddAuthenticationToPrincipalTemplateTest < ActiveSupport::TestCase
  setup do
    connection.remove_column(:users, :session_token_seed)
    connection.create_table :members do |table|
      table.string :email, null: false
    end
    members.create!(email: 'one@example.com')
    members.create!(email: 'two@example.com')
  end

  teardown do
    connection.drop_table(:members) if connection.table_exists?(:members)
    unless connection.column_exists?(:users, :session_token_seed)
      connection.add_column :users, :session_token_seed, :string, default: '', null: false
    end
    User.reset_column_information
  end

  test 'renders a portable backfill migration for the configured principal table' do
    rendered_migration.new.migrate(:up)
    members.reset_column_information

    column = connection.columns(:members).find { |candidate| candidate.name == 'session_token_seed' }

    assert column
    assert_not column.null
    assert_equal '', column.default

    seeds = members.order(:id).pluck(:session_token_seed)
    new_member = members.create!(email: 'three@example.com')

    assert_equal 2, seeds.length
    assert(seeds.all? { |seed| seed.match?(/\A[0-9a-f]{32}\z/) })
    assert_equal seeds.length, seeds.uniq.length
    assert_equal '', new_member.session_token_seed
  end

  test 'rolls back the configured principal migration without removing members' do
    migration = rendered_migration.new

    migration.migrate(:up)
    assert_nil rollback_error(migration)
    members.reset_column_information

    assert_not connection.column_exists?(:members, :session_token_seed)
    assert_equal 2, members.count
  end

  private

  # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  def connection
    ActiveRecord::Base.connection
  end

  # @return [Class]
  def members
    @members ||= Class.new(ActiveRecord::Base) do
      self.table_name = 'members'
    end
  end

  # @return [Class<ActiveRecord::Migration>]
  def rendered_migration
    scope = Module.new
    scope.module_eval(rendered_template, template_path)
    scope.const_get(:AddAuthenticationToPrincipal)
  end

  # @param migration [ActiveRecord::Migration]
  # @return [ActiveRecord::IrreversibleMigration, nil]
  def rollback_error(migration)
    migration.migrate(:down)
    nil
  rescue ActiveRecord::IrreversibleMigration => e
    e
  end

  # @return [String]
  def rendered_template
    ERB.new(File.read(template_path)).result_with_hash(principal_table_name: 'members')
  end

  # @return [String]
  def template_path
    File.expand_path(
      '../../../../lib/generators/vertiso/authentication/templates/add_authentication_to_principal.rb.tt',
      __dir__
    )
  end
end
