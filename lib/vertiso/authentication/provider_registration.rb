# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require_relative "omniauth/provider_configuration_error"
require_relative "omniauth/provider_registry"

module Vertiso
  module Authentication
    # Stores deferred host values for one known or generic OmniAuth strategy.
    class ProviderRegistration
      attr_reader :name, :profile, :strategy

      # Creates a provider registration without resolving host-owned values.
      #
      # @param name [String, Symbol] OmniAuth strategy name
      # @param strategy [String, Symbol, Class, nil] generic OmniAuth strategy
      # @param arguments [Array] generic positional strategy arguments
      # @param options [Hash, nil] generic strategy options
      # @param values [Hash{Symbol=>Object, #call}] provider values
      def initialize(
        name,
        strategy: nil,
        arguments: [],
        options: nil,
        **values
      )
        @name = name.to_sym
        @profile = Omniauth::ProviderRegistry.fetch(name)
        reject_known_strategy_override!(strategy) if profile && strategy
        reject_known_arguments!(arguments) if profile && arguments.any?
        @strategy = profile&.strategy || strategy || @name
        @argument_resolvers = freeze_value(copy_value(arguments))
        @value_resolvers = freeze_value(
          copy_value(values.merge(options || {}))
        )
      end

      # Resolves one coherent provider construction snapshot.
      #
      # @return [Array(Array, Hash)] positional arguments and keyword options
      def resolve
        construction = known? ? resolve_known : resolve_generic
        freeze_value(copy_value(construction))
      end

      # Returns resolved positional strategy arguments.
      #
      # @return [Array]
      def arguments
        resolve.fetch(0)
      end

      # Returns resolved keyword strategy options.
      #
      # @return [Hash]
      def options
        resolve.fetch(1)
      end

      # Returns whether this registration uses a built-in provider profile.
      #
      # @return [Boolean]
      def known?
        !profile.nil?
      end

      # Returns a representation that never resolves or displays host values.
      #
      # @return [String]
      def inspect
        "#<#{self.class} name=#{name.inspect} " \
          "strategy=#{strategy.inspect} known=#{known?} " \
          "configured_keys=#{configured_keys.inspect}>"
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
        value_resolvers[key]
      end

      # Returns configured names without resolving host values.
      #
      # @return [Array<String, Symbol>]
      def configured_keys
        keys = value_resolvers.keys
        keys += [:arguments] if argument_resolvers.any?
        keys.sort_by(&:to_s)
      end

      alias option_keys configured_keys

      private

      attr_reader :argument_resolvers, :value_resolvers

      # Prevents a host from bypassing a known profile's identity contract.
      #
      # @param strategy [String, Symbol, Class]
      # @return [void]
      # @raise [Vertiso::Authentication::Omniauth::ProviderConfigurationError]
      def reject_known_strategy_override!(_strategy)
        error = Omniauth::ProviderConfigurationError.new(
          "OAuth provider #{name} uses its registered provider profile and " \
          "does not accept a strategy override"
        )
        raise error, cause: nil
      end

      # Prevents silent loss of positional arguments owned by known profiles.
      #
      # @param _arguments [Array]
      # @return [void]
      # @raise [Vertiso::Authentication::Omniauth::ProviderConfigurationError]
      def reject_known_arguments!(_arguments)
        error = Omniauth::ProviderConfigurationError.new(
          "OAuth provider #{name} uses its registered provider profile and " \
          "does not accept positional arguments"
        )
        raise error, cause: nil
      end

      # Resolves one value tree containing literals and zero-argument callables.
      #
      # @param value [Object]
      # @return [Object]
      def resolve_value(value)
        case value
        when Array
          value.map { |entry| resolve_value(entry) }
        when Hash
          value.transform_values { |entry| resolve_value(entry) }
        else
          resolved = value.respond_to?(:call) ? value.call : value
          copy_value(resolved)
        end
      end

      # Resolves host values through a known provider profile.
      #
      # @return [Array(Array, Hash)]
      def resolve_known
        values = resolved_values
        validate_required_values!(values)
        [profile.arguments_for(values), profile.options_for(values)]
      end

      # Resolves an arbitrary OmniAuth strategy contract.
      #
      # @return [Array(Array, Hash)]
      def resolve_generic
        resolved_options = resolved_values.merge(
          name: name.to_s
        )
        [resolve_value(argument_resolvers), resolved_options]
      end

      # Resolves host keyword values once for one construction snapshot.
      #
      # @return [Hash]
      def resolved_values
        resolve_value(value_resolvers)
      end

      # Validates a known profile's required resolved host values.
      #
      # @param values [Hash]
      # @return [void]
      # @raise [Vertiso::Authentication::Omniauth::ProviderConfigurationError]
      def validate_required_values!(values)
        profile.required_keys.each do |key|
          next unless provider_value_blank?(values[key])

          error = Omniauth::ProviderConfigurationError.new(
            "OAuth provider #{name} requires nonblank #{key}"
          )
          raise error, cause: nil
        end
      end

      # Returns whether a resolved provider value is absent or blank.
      #
      # @param value [Object]
      # @return [Boolean]
      def provider_value_blank?(value)
        value.nil? ||
          (value.respond_to?(:empty?) && value.empty?) ||
          (value.is_a?(String) && value.strip.empty?)
      end

      # Recursively freezes a resolved provider construction snapshot.
      #
      # @param value [Object]
      # @return [Object]
      def freeze_value(value)
        case value
        when Array
          value.each { |entry| freeze_value(entry) }
        when Hash
          value.each_value { |entry| freeze_value(entry) }
        when String
          value.freeze
        end
        value.freeze if value.is_a?(Array) || value.is_a?(Hash)
        value
      end

      # Recursively copies mutable construction containers and strings.
      #
      # Unknown scalar objects remain host-owned and are never frozen.
      #
      # @param value [Object]
      # @return [Object]
      def copy_value(value)
        case value
        when Array
          value.map { |entry| copy_value(entry) }
        when Hash
          value.each_with_object({}) do |(key, entry), copy|
            copy[copy_value(key)] = copy_value(entry)
          end
        when String
          value.dup
        else
          value
        end
      end
    end
  end
end
