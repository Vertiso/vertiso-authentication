# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Normalizes authentication delivery transport failures for controllers.
    module DispatchHandling
      private

      # Runs a delivery operation and translates production transport failures.
      #
      # @param label [String]
      # @yieldreturn [Object] truthy on success, false on silent failure
      # @return [Boolean]
      def safely_dispatch(label:)
        result = yield
        return true unless result == false

        Rails.logger.error(
          "[#{label}] dispatch returned false " \
          "(adapter swallowed enqueue error)"
        )
        report_dispatch_error(
          RuntimeError.new("[#{label}] deliver_later returned false")
        )
        false
      rescue StandardError => error
        raise unless dispatch_transport_error?(error)

        Rails.logger.error(
          "[#{label}] dispatch failed: #{error.class}: #{error.message}"
        )
        report_dispatch_error(error)
        false
      end

      # Reports a dispatch failure through the optional host callable.
      #
      # @param error [StandardError]
      # @return [void]
      def report_dispatch_error(error)
        reporter =
          Vertiso::Authentication.configuration.dispatch_error_reporter
        return unless reporter

        reporter.call(error)
      rescue StandardError => reporting_error
        Rails.logger.warn(
          "[AuthenticationDispatch] report failed: " \
          "#{reporting_error.class}: #{reporting_error.message}"
        )
      end

      # @param error [StandardError]
      # @return [Boolean]
      def dispatch_transport_error?(error)
        error.is_a?(ActiveJob::EnqueueError) ||
          (defined?(RedisClient::Error) && error.is_a?(RedisClient::Error)) ||
          (defined?(Redis::BaseError) && error.is_a?(Redis::BaseError))
      end
    end
  end
end
