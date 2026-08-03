# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Adds portable password and principal-identity behavior to a host model.
    module Authenticatable
      extend ActiveSupport::Concern

      MIN_PASSWORD_LENGTH = 8
      MAX_PASSWORD_LENGTH = 40
      VALID_PASSWORD_REGEX = /\A.*(?=.*\d)(?=.*[!_@#$%^&*-])(?=.*[a-z])(?=.*[A-Z]).*\z/

      included do
        has_secure_password

        before_validation :normalize_authentication_identity_attributes

        validate :authentication_identity_attributes_are_present
        validate :authentication_identity_attributes_are_unique

        validates :password,
                  presence: true,
                  length: { minimum: MIN_PASSWORD_LENGTH, maximum: MAX_PASSWORD_LENGTH },
                  format: { with: VALID_PASSWORD_REGEX },
                  if: :password_required?
      end

      class_methods do
        # Finds a principal by its configured normalized email address.
        #
        # @param email [String]
        # @return [ApplicationRecord, nil]
        def find_email(email:)
          find_by(configured_email_attribute => normalize_email(email))
        end

        # Finds a principal by its configured email address or user name.
        #
        # @param login [String]
        # @return [ApplicationRecord, nil]
        def find_login(login)
          normalized = normalize_login(login)

          find_by(configured_email_attribute => normalized) ||
            find_by(configured_user_name_attribute => normalized)
        end

        # Authenticates a principal by its configured email address or user name.
        #
        # @param login [String]
        # @param password [String]
        # @return [ApplicationRecord, false, nil]
        def authenticate(login, password)
          find_login(login)&.authenticate(password)
        end

        private

        # @return [Symbol]
        def configured_email_attribute
          Vertiso::Authentication.configuration.email_attribute
        end

        # @return [Symbol]
        def configured_user_name_attribute
          Vertiso::Authentication.configuration.user_name_attribute
        end

        # @param email [String]
        # @return [String]
        def normalize_email(email)
          normalize_login(email)
        end

        # @param login [String]
        # @return [String]
        def normalize_login(login)
          login.to_s.strip.downcase
        end
      end

      private

      # @return [Boolean]
      def password_required?
        password.present?
      end

      # Normalizes configured email and user-name attributes before validation.
      #
      # @return [void]
      def normalize_authentication_identity_attributes
        normalize_authentication_attribute(configured_email_attribute)
        normalize_authentication_attribute(configured_user_name_attribute)
      end

      # @return [void]
      def authentication_identity_attributes_are_present
        authentication_identity_attributes.each do |attribute|
          errors.add(attribute, :blank) if public_send(attribute).blank?
        end
      end

      # @return [void]
      def authentication_identity_attributes_are_unique
        authentication_identity_attributes.each do |attribute|
          value = public_send(attribute)
          next if value.blank?

          scope = self.class.where(self.class.arel_table[attribute].lower.eq(value.downcase))
          scope = scope.where.not(id:) if persisted?
          errors.add(attribute, :taken) if scope.exists?
        end
      end

      # @return [Array<Symbol>]
      def authentication_identity_attributes
        [configured_email_attribute, configured_user_name_attribute]
      end

      # @param attribute [Symbol]
      # @return [void]
      def normalize_authentication_attribute(attribute)
        public_send("#{attribute}=", public_send(attribute).to_s.strip.downcase)
      end

      # @return [Symbol]
      def configured_email_attribute
        Vertiso::Authentication.configuration.email_attribute
      end

      # @return [Symbol]
      def configured_user_name_attribute
        Vertiso::Authentication.configuration.user_name_attribute
      end
    end
  end
end
