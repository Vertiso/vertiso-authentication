# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Stores deferred host values for one OmniAuth strategy registration.
    class ProviderRegistration
      attr_reader :name

      # Creates a provider registration without resolving host values.
      #
      # @param name [String, Symbol] OmniAuth strategy name
      # @param resolvers [Hash{Symbol=>Object, #call}] literal values or
      #   zero-argument callables
      def initialize(name, **resolvers)
        @name = name.to_sym
        @resolvers = resolvers.freeze
      end

      # Resolves provider values for middleware construction.
      #
      # @return [Hash]
      def options
        resolvers.transform_values do |value|
          value.respond_to?(:call) ? value.call : value
        end
      end

      # Returns a representation that never resolves or displays host values.
      #
      # @return [String]
      def inspect
        "#<#{self.class} name=#{name.inspect} resolver_keys=#{resolvers.keys.inspect}>"
      end

      # Returns one host value without resolving a callable.
      #
      # This supports request-time resolvers such as the development principal
      # lookup while keeping provider credentials deferred until middleware
      # construction.
      #
      # @param key [Symbol]
      # @return [Object, #call, nil]
      def value_resolver(key)
        resolvers[key]
      end

      # Returns configured option names without resolving their values.
      #
      # @return [Array<Symbol>]
      def option_keys
        resolvers.keys
      end

      private

      attr_reader :resolvers
    end
  end
end
