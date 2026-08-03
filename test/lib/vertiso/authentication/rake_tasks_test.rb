# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "rake"

# Pins the public local-gate task names and aggregate quality graph.
class VertisoAuthenticationRakeTasksTest < ActiveSupport::TestCase
  REQUIRED_TASKS = %w[
    test:sqlite
    test:postgresql
    quality:rubocop
    quality:brakeman
    quality:audit
    package:build
    package:validate
    ci
  ].freeze

  AGGREGATE_PREREQUISITES = %w[
    test:sqlite
    test:postgresql
    quality:rubocop
    quality:brakeman
    quality:audit
    package:validate
  ].freeze

  setup do
    @previous_application = Rake.application
    Rake.application = Rake::Application.new
    Object.send(:remove_const, :GEMSPEC_PATH) if Object.const_defined?(:GEMSPEC_PATH)
    Object.send(:remove_const, :PACKAGE_DIRECTORY) if Object.const_defined?(:PACKAGE_DIRECTORY)
    load File.expand_path("../../../../Rakefile", __dir__)
  end

  teardown do
    Rake.application = @previous_application
  end

  test "defines named adapter quality and package gates" do
    REQUIRED_TASKS.each do |name|
      assert Rake::Task.task_defined?(name), "Expected rake task #{name}"
    end
  end

  test "complete aggregate gate includes every required gate" do
    assert_equal AGGREGATE_PREREQUISITES,
                 Rake::Task["ci"].prerequisites
  end
end
