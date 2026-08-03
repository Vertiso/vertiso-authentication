# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Handles minimal host-principal registration.
    class RegistrationsController < ::ApplicationController
      # Renders the principal registration form.
      #
      # @return [void]
      def new
        @principal = authentication_configuration.principal_class.new
      end

      # Creates and logs in a host principal from authentication fields only.
      #
      # @return [void]
      def create
        @principal = authentication_configuration.principal_class.new(
          registration_attributes
        )

        if @principal.save
          log_in(principal: @principal)
          redirect_to registration_destination(@principal)
        else
          render :new, status: :unprocessable_content
        end
      end

      private

      # @return [ActionController::Parameters]
      def permitted_registration_parameters
        params.expect(
          registration: %i[
            email
            user_name
            password
            password_confirmation
          ]
        )
      end

      # @return [Hash]
      def registration_attributes
        permitted = permitted_registration_parameters
        {
          authentication_configuration.email_attribute => permitted[:email],
          authentication_configuration.user_name_attribute => permitted[:user_name],
          password: permitted[:password],
          password_confirmation: permitted[:password_confirmation]
        }
      end

      # @param principal [ApplicationRecord]
      # @return [String]
      def registration_destination(principal)
        callable = authentication_configuration.post_registration_destination
        return callable.call(self, principal) if callable

        main_app.root_path
      end

      # @return [Vertiso::Authentication::Configuration]
      def authentication_configuration
        Vertiso::Authentication.configuration
      end
    end
  end
end
