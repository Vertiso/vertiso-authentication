# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rails/engine"
require "view_component/base"
require_relative "encryption_configuration"
require_relative "omniauth/provider_configuration_error"
require_relative "omniauth/provider_registry"
require_relative "provider_registration"
require_relative "omniauth/middleware"

module Vertiso
  # Namespace for the Vertiso authentication Rails engine.
  module Authentication
    # Rails engine providing isolated Vertiso authentication functionality.
    class Engine < ::Rails::Engine
      isolate_namespace Vertiso::Authentication

      initializer "vertiso_authentication.omniauth_middleware" do |application|
        application.middleware.use Omniauth::Middleware
      end

      initializer "vertiso_authentication.active_record_encryption",
                  after: :load_config_initializers,
                  before: :build_middleware_stack do
        EncryptionConfiguration.validate!
      end
    end
  end
end
