# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "bundler/setup"
require "vertiso/authentication"

dummy_name = ENV.fetch("DUMMY_APP", "dummy_standard")
ENV["RAILS_ENV"] ||= "test"
require_relative "#{dummy_name}/config/environment"

# Dummy schemas load below so migration tests control engine migrations directly.
ActiveRecord.maintain_test_schema = false

require "rails/test_help"

load Rails.root.join("db/schema.rb")
