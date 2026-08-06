# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Validates Rails encryption before provider credentials can be persisted.
    module EncryptionConfiguration
      GUIDE_URL =
        "https://guides.rubyonrails.org/active_record_encryption.html".freeze
      PROBE = "vertiso-authentication-encryption-check".freeze
      ERROR_MESSAGE = <<~MESSAGE.squish.freeze
        Vertiso Authentication OAuth providers require working Active Record
        Encryption keys. Configure and verify the host encryption keys before
        boot. See the Active Record Encryption guide: #{GUIDE_URL}
      MESSAGE

      class << self
        # Verifies that the host encryption context can round-trip a value.
        #
        # Password-only hosts without an OAuth provider do not persist provider
        # credentials and therefore do not require this validation.
        #
        # @param configuration [Vertiso::Authentication::Configuration]
        # @return [void]
        # @raise [ActiveRecord::Encryption::Errors::Configuration]
        def validate!(configuration: Vertiso::Authentication.configuration)
          return if configuration.oauth_providers.empty?

          ciphertext = ActiveRecord::Encryption.encryptor.encrypt(PROBE)
          plaintext = ActiveRecord::Encryption.encryptor.decrypt(ciphertext)
          raise_configuration_error unless plaintext == PROBE
        rescue ActiveRecord::Encryption::Errors::Base
          raise_configuration_error
        end

        private

        # Raises the redacted host-configuration error without retaining a
        # provider or encryption-library exception as its cause.
        #
        # @return [void]
        # @raise [ActiveRecord::Encryption::Errors::Configuration]
        def raise_configuration_error
          error = ActiveRecord::Encryption::Errors::Configuration.new(
            ERROR_MESSAGE
          )
          raise error, cause: nil
        end
      end
    end
  end
end
