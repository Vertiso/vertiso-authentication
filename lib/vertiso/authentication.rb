# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rails"
require_relative "authentication/version"
require_relative "authentication/engine"
require_relative "authentication/configuration"
require_relative "../../app/models/concerns/vertiso/authentication/authenticatable"

# Root namespace for Vertiso libraries.
module Vertiso
  # Namespace for the Vertiso authentication Rails engine.
  module Authentication
    class << self
      # Yields the engine configuration to the host application.
      #
      # @yieldparam configuration [Vertiso::Authentication::Configuration]
      # @return [Vertiso::Authentication::Configuration]
      def configure
        yield configuration
      end

      # Returns the current engine configuration.
      #
      # @return [Vertiso::Authentication::Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Resets configuration to conventional host defaults.
      #
      # @return [Vertiso::Authentication::Configuration]
      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
