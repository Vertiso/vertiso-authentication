# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "bundler/setup"
require "vertiso/authentication"

dummy_name = ENV.fetch("DUMMY_APP", "dummy_standard")
ENV["RAILS_ENV"] ||= "test"
require_relative "#{dummy_name}/config/environment"

require "rails/test_help"
