# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    module Omniauth
      # Immutable construction contract for one known OmniAuth provider.
      class ProviderProfile
        attr_reader :gem_name,
                    :name,
                    :require_path,
                    :required_keys,
                    :strategy

        # Creates a known provider construction profile.
        #
        # @param name [String, Symbol] public provider key
        # @param strategy [String, Symbol, Class] OmniAuth strategy
        # @param gem_name [String, nil] optional strategy gem name
        # @param require_path [String, nil] optional strategy require path
        # @param required_keys [Array<Symbol>] required host configuration
        # @param arguments [#call] positional argument builder
        # @param options [#call] keyword option builder
        # @param setup [#call, nil] selected-provider setup hook
        def initialize(
          name:,
          strategy:,
          gem_name: nil,
          require_path: nil,
          required_keys: [],
          arguments: ->(_values) { [] },
          options: ->(values) { values },
          setup: nil
        )
          @name = name.to_sym
          @strategy = immutable_metadata(strategy)
          @gem_name = immutable_metadata(gem_name)
          @require_path = immutable_metadata(require_path)
          @required_keys = required_keys.map(&:to_sym).freeze
          @arguments_builder = arguments
          @options_builder = options
          @setup = setup
          freeze
        end

        # Builds positional strategy arguments without mutating host values.
        #
        # @param values [Hash]
        # @return [Array]
        def arguments_for(values)
          arguments_builder.call(values.dup)
        end

        # Builds keyword strategy options without mutating host values.
        #
        # @param values [Hash]
        # @return [Hash]
        def options_for(values)
          options_builder.call(values.dup)
        end

        # Loads the optional strategy selected by the host.
        #
        # @return [Boolean, nil]
        # @raise [LoadError]
        def load_strategy!
          Kernel.require(require_path) if require_path
        end

        # Installs selected-provider compatibility behavior.
        #
        # @return [void]
        def install!
          setup&.call
        end

        private

        attr_reader :arguments_builder, :options_builder, :setup

        # Copies and freezes mutable public profile metadata.
        #
        # @param value [Object]
        # @return [Object]
        def immutable_metadata(value)
          value.is_a?(String) ? value.dup.freeze : value
        end
      end
    end
  end
end
