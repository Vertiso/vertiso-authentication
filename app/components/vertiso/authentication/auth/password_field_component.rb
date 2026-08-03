# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    module Auth
      # Renders password and confirmation fields for account creation.
      class PasswordFieldComponent < ViewComponent::Base
        attr_reader :form, :required, :theme

        # @param form [ActionView::Helpers::FormBuilder] surrounding form
        # @param required [Boolean] whether both fields are required
        # @param theme [Vertiso::Authentication::Theme] semantic presentation
        def initialize(
          form:,
          required: true,
          theme: Vertiso::Authentication.configuration.theme
        )
          super()
          @form = form
          @required = required
          @theme = theme
        end
      end
    end
  end
end
