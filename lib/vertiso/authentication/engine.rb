# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rails/engine"
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
    end
  end
end
