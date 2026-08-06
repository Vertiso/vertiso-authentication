# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "bundler/setup"

dummy_name = ENV.fetch("DUMMY_APP", "dummy_standard")
ENV["RAILS_ENV"] ||= "test"
require "vertiso/authentication"
require_relative "#{dummy_name}/config/environment"

ACTIVE_RECORD_ENCRYPTION_TEST_KEYS = {
  primary_key: "vertiso-authentication-test-primary-key",
  deterministic_key: "vertiso-authentication-test-deterministic-key",
  key_derivation_salt: "vertiso-authentication-test-key-derivation-salt"
}.freeze

ActiveRecord::Encryption.configure(**ACTIVE_RECORD_ENCRYPTION_TEST_KEYS)

# Dummy schemas load below so migration tests control engine migrations directly.
ActiveRecord.maintain_test_schema = false

require "rails/test_help"

load Rails.root.join("db/schema.rb")
