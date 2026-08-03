# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rails/engine"

module Vertiso
  # Namespace for the Vertiso authentication Rails engine.
  module Authentication
    # Rails engine providing isolated Vertiso authentication functionality.
    class Engine < ::Rails::Engine
      isolate_namespace Vertiso::Authentication
    end
  end
end
