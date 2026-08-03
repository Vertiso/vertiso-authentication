# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Adds portable password and principal-identity behavior to a host model.
    module Authenticatable
      extend ActiveSupport::Concern

      MIN_PASSWORD_LENGTH = 8
      MAX_PASSWORD_LENGTH = 40
      MIN_EMAIL_LENGTH = 6
      MAX_EMAIL_LENGTH = 255
      VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i
      VALID_PASSWORD_REGEX = /\A.*(?=.*\d)(?=.*[!_@#$%^&*-])(?=.*[a-z])(?=.*[A-Z]).*\z/

      included do
        has_secure_password

        # Returns authentication-session metadata belonging to this principal.
        has_many :authentication_sessions,
                 as: :principal,
                 class_name: "Vertiso::Authentication::AuthenticationSession"

        # Returns linked external identities belonging to this principal.
        has_many :authentication_oauth_accounts,
                 as: :principal,
                 class_name: "Vertiso::Authentication::UserOauthAccount",
                 dependent: :destroy

        before_create :initialize_session_token_seed
        before_validation :normalize_authentication_identity_attributes

        validate :authentication_identity_attributes_are_present
        validate :authentication_identity_attributes_are_unique
        validate :authentication_email_is_valid

        validates :password,
                  presence: true,
                  length: { minimum: MIN_PASSWORD_LENGTH, maximum: MAX_PASSWORD_LENGTH },
                  format: { with: VALID_PASSWORD_REGEX },
                  if: :password_required?

        generates_token_for(
          :remember_token,
          expires_in: Vertiso::Authentication.configuration.remember_token_lifetime
        ) do
          [password_salt&.last(10), session_token_seed]
        end

        generates_token_for(
          :email_verification,
          expires_in: Vertiso::Authentication.configuration.email_confirmation_lifetime
        ) do
          public_send(configured_email_attribute)
        end

        generates_token_for(
          :password_reset,
          expires_in: Vertiso::Authentication.configuration.password_reset_lifetime
        ) do
          [password_salt&.last(10), public_send(configured_email_attribute)]
        end
      end

      class_methods do
        # Finds a principal by its configured normalized email address.
        #
        # @param email [String]
        # @return [ApplicationRecord, nil]
        def find_email(email:)
          normalized_email = normalize_email(email)
          return nil if normalized_email.blank?

          find_by(configured_email_attribute => normalized_email) ||
            Vertiso::Authentication::UserOauthAccount.find_by(
              email: normalized_email,
              principal_type: polymorphic_name
            )&.principal
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
          return nil if login.blank? || password.blank?

          principal = find_login(login)
          return principal.authenticate(password) if principal

          linked_account = Vertiso::Authentication::UserOauthAccount.find_by(
            email: normalize_login(login),
            principal_type: polymorphic_name
          )
          linked_account&.principal&.authenticate(password)
        end

        # Returns whether a string satisfies the production email contract.
        #
        # @param value [Object]
        # @return [Boolean]
        def valid_email?(value)
          return false unless value.is_a?(String)

          value.length.between?(MIN_EMAIL_LENGTH, MAX_EMAIL_LENGTH) &&
            value.match?(VALID_EMAIL_REGEX)
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

      # Initializes a portable, rotatable browser-session invalidation seed.
      #
      # @return [void]
      def initialize_session_token_seed
        self.session_token_seed = SecureRandom.hex(16) if session_token_seed.blank?
      end

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

      # Validates the configured canonical email against production rules.
      #
      # @return [void]
      def authentication_email_is_valid
        email = public_send(configured_email_attribute)
        return if email.blank? || self.class.valid_email?(email)

        errors.add(configured_email_attribute, :invalid)
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

      # @return [Symbol]
      def configured_email_confirmed_at_attribute
        Vertiso::Authentication.configuration.email_confirmed_at_attribute
      end

      private :initialize_session_token_seed,
              :password_required?,
              :normalize_authentication_identity_attributes,
              :authentication_identity_attributes_are_present,
              :authentication_identity_attributes_are_unique,
              :authentication_email_is_valid,
              :authentication_identity_attributes,
              :normalize_authentication_attribute,
              :configured_email_attribute,
              :configured_user_name_attribute,
              :configured_email_confirmed_at_attribute

      # @return [Boolean] whether the configured email is verified
      def email_verified?
        public_send(configured_email_confirmed_at_attribute).present?
      end

      # Marks the configured email confirmation timestamp as verified.
      #
      # @return [Boolean]
      def verify_email
        update(configured_email_confirmed_at_attribute => Time.zone.now)
      end

      # Rotates the browser-session seed and invalidates every remember token.
      #
      # @return [String] the freshly generated session token seed
      def reset_session_token!
        update!(session_token_seed: SecureRandom.hex(16))
        session_token_seed
      end
    end
  end
end
