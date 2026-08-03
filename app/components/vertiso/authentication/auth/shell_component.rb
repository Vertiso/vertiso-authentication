# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    module Auth
      # Frames a host-independent authentication surface.
      class ShellComponent < ViewComponent::Base
        attr_reader :home_path, :subtitle, :theme, :title

        # @param title [String] page heading
        # @param home_path [String] host home destination
        # @param subtitle [String, nil] optional supporting copy
        # @param theme [Vertiso::Authentication::Theme] semantic presentation
        def initialize(
          title:,
          home_path:,
          subtitle: nil,
          theme: Vertiso::Authentication.configuration.theme
        )
          super()
          @home_path = home_path
          @subtitle = subtitle
          @theme = theme
          @title = title
        end
      end
    end
  end
end
