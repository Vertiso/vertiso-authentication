# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "generator_test_helper"
require "generators/vertiso/authentication/views_generator"

class VertisoAuthenticationViewsGeneratorTest < Rails::Generators::TestCase
  include VertisoAuthenticationGeneratorTestHelper

  class RejectingCollisionShell < Thor::Shell::Basic
    attr_reader :collisions

    def initialize
      super
      @collisions = []
    end

    def file_collision(destination)
      collisions << destination
      false
    end
  end

  tests Vertiso::Authentication::Generators::ViewsGenerator
  destination File.expand_path(
    "../../../../tmp/views_generator",
    __dir__
  )

  setup do
    prepare_destination
  end

  test "copies every overridable component class and template" do
    run_generator

    %w[
      login_form
      oauth_providers
      password_field
      shell
      signup_form
    ].each do |component|
      assert_file(
        "app/components/vertiso/authentication/auth/#{component}_component.rb"
      )
      assert_file(
        "app/components/vertiso/authentication/auth/#{component}_component.html.erb"
      )
    end
  end

  test "keeps an existing host override through normal conflict handling" do
    override_path =
      "app/components/vertiso/authentication/auth/shell_component.html.erb"
    write_host_file(override_path, "HOST-OVERRIDE\n")

    generator = Vertiso::Authentication::Generators::ViewsGenerator.new(
      [],
      {},
      destination_root:
    )
    shell = RejectingCollisionShell.new
    generator.shell = shell
    generator.invoke_all

    assert_file override_path, "HOST-OVERRIDE\n"
    assert_includes(
      shell.collisions,
      File.join(destination_root, override_path)
    )
  end
end
