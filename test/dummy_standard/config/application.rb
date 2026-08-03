# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "boot"

require "rails/all"

module DummyStandard
  # Configures the conventional-principal dummy Rails application.
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.1
    config.eager_load = false
    config.active_storage.variant_processor = :disabled
    config.action_controller.allow_forgery_protection = false
    config.logger = ActiveSupport::Logger.new(IO::NULL)
    config.secret_key_base = "dummy-standard-test-secret-key-base"
  end
end
