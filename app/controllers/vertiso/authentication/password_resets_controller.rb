# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Handles anonymous password-reset requests and signed-token completion.
    class PasswordResetsController < ::ApplicationController
      rate_limit to: 10,
                 within: 1.hour,
                 by: -> { request.remote_ip },
                 with: -> { render_create_rate_limited },
                 name: "vertiso-authentication-forgot-password-per-hour",
                 only: :create

      # Renders the public password-reset request form.
      #
      # @return [void]
      def new
        if authenticated?
          redirect_to main_app.root_path,
                      notice: t("vertiso.authentication.password_resets.already_signed_in")
          return
        end

        @email = params[:email].to_s
      end

      # Dispatches reset mail for a verified email while returning a neutral response.
      #
      # @return [void]
      def create
        if authenticated?
          redirect_to main_app.root_path,
                      notice: t("vertiso.authentication.password_resets.already_signed_in")
          return
        end

        email = params[:email].to_s.strip
        principal = email.present? ? principal_class.find_email(email:) : nil

        if principal&.email_verified?
          token = principal.generate_token_for(:password_reset)
          safely_dispatch_reset(principal:, token:)
        end

        redirect_to login_path,
                    notice: t("vertiso.authentication.password_resets.email_sent")
      end

      # Renders the password form after validating the signed token.
      #
      # @return [void]
      def edit
        @principal = principal_class.find_by_token_for(
          :password_reset,
          params[:token]
        )

        if @principal.nil?
          redirect_to login_path,
                      alert: t("vertiso.authentication.password_resets.invalid_link")
          return
        end

        log_out if authenticated?
        @token = params[:token]
      end

      # Changes the password under lock after immediately revalidating the token.
      #
      # @return [void]
      def update
        @principal = principal_class.find_by_token_for(
          :password_reset,
          params[:token]
        )
        @token = params[:token]

        if @principal.nil?
          redirect_to login_path,
                      alert: t("vertiso.authentication.password_resets.invalid_link")
          return
        end

        log_out if authenticated?
        credentials = password_params

        if credentials[:password].blank?
          @principal.errors.add(
            :password,
            t("vertiso.authentication.password_resets.password_blank")
          )
          render :edit, status: :unprocessable_content
        elsif credentials[:password_confirmation].blank?
          @principal.errors.add(
            :password_confirmation,
            t("vertiso.authentication.password_resets.password_blank")
          )
          render :edit, status: :unprocessable_content
        else
          update_password_under_lock(credentials:)
        end
      end

      private

      # @param credentials [ActionController::Parameters]
      # @return [void]
      def update_password_under_lock(credentials:)
        @principal.with_lock do
          if principal_class.find_by_token_for(:password_reset, @token).nil?
            redirect_to login_path,
                        alert: t("vertiso.authentication.password_resets.invalid_link")
          elsif @principal.update(
            password: credentials[:password],
            password_confirmation: credentials[:password_confirmation]
          )
            log_in(principal: @principal)
            flash[:notice] =
              t("vertiso.authentication.password_resets.password_changed")
            redirect_to authentication_destination(@principal)
          else
            render :edit, status: :unprocessable_content
          end
        end
      end

      # @return [ActionController::Parameters]
      def password_params
        params.expect(user: %i[password password_confirmation])
      end

      # @param principal [ApplicationRecord]
      # @return [String]
      def authentication_destination(principal)
        callable = authentication_configuration.post_authentication_destination
        return callable.call(self, principal) if callable

        main_app.root_path
      end

      # @param principal [ApplicationRecord]
      # @param token [String]
      # @return [Boolean]
      def safely_dispatch_reset(principal:, token:)
        result = AuthenticationMailer.reset(principal, token).deliver_later
        result != false
      rescue StandardError => error
        raise unless dispatch_transport_error?(error)

        Rails.logger.error(
          "[PasswordReset] dispatch failed: #{error.class}: #{error.message}"
        )
        false
      end

      # @param error [StandardError]
      # @return [Boolean]
      def dispatch_transport_error?(error)
        error.is_a?(ActiveJob::EnqueueError) ||
          (defined?(RedisClient::Error) && error.is_a?(RedisClient::Error)) ||
          (defined?(Redis::BaseError) && error.is_a?(Redis::BaseError))
      end

      # @return [void]
      def render_create_rate_limited
        redirect_to forgot_password_path,
                    alert: t("vertiso.authentication.password_resets.rate_limited"),
                    status: :see_other
      end

      # @return [Class]
      def principal_class
        authentication_configuration.principal_class
      end

      # @return [Vertiso::Authentication::Configuration]
      def authentication_configuration
        Vertiso::Authentication.configuration
      end
    end
  end
end
