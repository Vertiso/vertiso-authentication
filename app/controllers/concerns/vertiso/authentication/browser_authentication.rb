# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "uri"

module Vertiso
  module Authentication
    # Provides production-compatible browser authentication to host controllers.
    module BrowserAuthentication
      extend ActiveSupport::Concern

      HTTP_CONTINUATION_SCHEMES = %w[http https].freeze
      INVALID_PERCENT_ESCAPE = /%(?![0-9A-Fa-f]{2})/
      UNSAFE_CONTINUATION_CHARACTER = /[\\\x00-\x1F\x7F]/

      included do
        helper_method :current_principal, :authenticated? if respond_to?(:helper_method)
      end

      # Returns the authenticated host principal for the current request.
      #
      # @return [ApplicationRecord, nil]
      def current_principal
        @current_principal ||= begin
          principal = authenticate_principal_from_remember_token
          touch_authentication_session(principal:) if principal
          principal
        end
      end

      # Returns whether the current request has an authenticated principal.
      #
      # @return [Boolean]
      def authenticated?
        current_principal.present?
      end

      # Logs in a principal after rotating the Rails session.
      #
      # @param principal [ApplicationRecord]
      # @return [void]
      def log_in(principal:)
        return if principal.nil?

        @current_principal = principal
        forward_to_url = session[:forward_to_url]
        reset_session
        session[:forward_to_url] = forward_to_url if forward_to_url
        remember(principal)
        persist_authentication_session(principal:)
      end

      # Logs out the current principal and expires its session metadata.
      #
      # @return [void]
      def log_out
        current_principal
        expire_authentication_session
        @current_principal = nil
        reset_session
        forget
      end

      # Stores a GET request URL for continuation after authentication.
      #
      # @return [void]
      def store_location
        session[:forward_to_url] = request.original_url if request.get? && !request.xhr?
      end

      # Returns and clears a saved continuation as a same-origin relative URL.
      #
      # @return [String, nil]
      def recall_location
        url = session.delete(:forward_to_url)
        return unless url

        safe_continuation_location(url:)
      rescue StandardError
        nil
      end

      private

      # Converts a stored location to a validated relative path and query.
      #
      # @param url [Object]
      # @return [String, nil]
      def safe_continuation_location(url:)
        return unless url.is_a?(String) && url.valid_encoding?

        uri = URI.parse(url)
        return unless safe_continuation_uri?(uri)

        decoded_path = safely_decode_continuation_component(uri.path)
        decoded_query = safely_decode_continuation_component(uri.query) if uri.query
        return unless safe_continuation_path?(decoded_path)
        return if uri.query && !safe_continuation_component?(decoded_query)

        uri.query ? "#{uri.path}?#{uri.query}" : uri.path
      end

      # @param uri [URI::Generic]
      # @return [Boolean]
      def safe_continuation_uri?(uri)
        return false if uri.opaque
        return uri.host.nil? if uri.scheme.nil?
        return false unless HTTP_CONTINUATION_SCHEMES.include?(uri.scheme.downcase)

        uri.host&.casecmp?(request.host)
      end

      # @param component [String]
      # @return [String, nil]
      def safely_decode_continuation_component(component)
        return if component.match?(INVALID_PERCENT_ESCAPE)

        decoded = URI::RFC2396_PARSER.unescape(component)
        decoded.force_encoding(Encoding::UTF_8)
        decoded if decoded.valid_encoding?
      end

      # @param path [String, nil]
      # @return [Boolean]
      def safe_continuation_path?(path)
        return false if path.nil? || !safe_continuation_component?(path)

        path.start_with?("/") && !path.start_with?("//")
      end

      # @param component [String, nil]
      # @return [Boolean]
      def safe_continuation_component?(component)
        !component.nil? && !component.match?(UNSAFE_CONTINUATION_CHARACTER)
      end

      # @return [String]
      def authentication_session_identifier
        identifier = session.id
        identifier.respond_to?(:public_id) ? identifier.public_id : identifier.to_s
      end

      # @param principal [ApplicationRecord]
      # @return [void]
      def remember(principal)
        forget
        token = principal.generate_token_for(:remember_token)
        cookies.permanent.encrypted[remember_cookie_key] = {
          value: token,
          httponly: !Rails.env.test?,
          secure: Rails.env.production?
        }
        session[:remember_token] = token
      end

      # @return [void]
      def forget
        cookies.delete(remember_cookie_key)
      end

      # @return [ApplicationRecord, nil]
      def authenticate_principal_from_remember_token
        token = begin
          cookies.encrypted[remember_cookie_key]
        rescue StandardError
          nil
        end
        token ||= session[:remember_token]
        principal = authentication_configuration.principal_class.find_by_token_for(
          :remember_token,
          token
        )
        forget if principal.nil?
        principal
      end

      # @param principal [ApplicationRecord]
      # @return [void]
      def persist_authentication_session(principal:)
        now = Time.current
        authentication_session = AuthenticationSession.find_or_initialize_by(
          session_identifier: authentication_session_identifier
        )
        authentication_session.update!(
          principal:,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          last_activity_at: now,
          expires_at: now + authentication_configuration.authentication_session_lifetime
        )
      end

      # @param principal [ApplicationRecord]
      # @return [void]
      def touch_authentication_session(principal:)
        AuthenticationSession.find_by(
          principal:,
          session_identifier: authentication_session_identifier
        )&.touch_activity!
      end

      # @return [void]
      def expire_authentication_session
        AuthenticationSession.find_by(
          session_identifier: authentication_session_identifier
        )&.update!(expires_at: Time.current)
      end

      # @return [Vertiso::Authentication::Configuration]
      def authentication_configuration
        Vertiso::Authentication.configuration
      end

      # @return [Symbol]
      def remember_cookie_key
        authentication_configuration.remember_cookie_key
      end
    end
  end
end
