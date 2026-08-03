# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rails/generators"

module Vertiso
  module Authentication
    module Generators
      # Copies engine components into a host for application-level overrides.
      class ViewsGenerator < Rails::Generators::Base
        COMPONENTS = %w[
          login_form
          oauth_providers
          password_field
          shell
          signup_form
        ].freeze

        source_root File.expand_path(
          "../../../../app/components",
          __dir__
        )

        # Copies each default class and template through Rails conflict handling.
        #
        # @return [void]
        def copy_components
          COMPONENTS.each do |component|
            copy_component(component:)
          end
        end

        private

        # @param component [String] component basename
        # @return [void]
        def copy_component(component:)
          %w[rb html.erb].each do |extension|
            path =
              "vertiso/authentication/auth/#{component}_component.#{extension}"
            copy_file path, "app/components/#{path}"
          end
        end
      end
    end
  end
end
