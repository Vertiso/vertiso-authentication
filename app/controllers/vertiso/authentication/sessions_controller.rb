# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

module Vertiso
  module Authentication
    # Handles password-backed browser login and logout.
    class SessionsController < ::ApplicationController
      include DispatchHandling

      PENDING_OAUTH_TTL = 10.minutes
      private_constant :PENDING_OAUTH_TTL

      # Renders the password login form.
      #
      # @return [void]
      def new
        redirect_to authentication_destination(current_principal) if authenticated?
      end

      # Authenticates configured principal credentials.
      #
      # @return [void]
      def create
        credentials = params.expect(session: %i[login password])
        principal = authentication_configuration.principal_class.authenticate(
          credentials[:login].to_s.strip,
          credentials[:password].to_s
        )

        if principal
          complete_login(principal:)
        else
          flash.now[:alert] = t("vertiso.authentication.sessions.invalid_credentials")
          render :new, status: :unprocessable_content
        end
      end

      # Handles an OmniAuth callback for login, linking, or signup.
      #
      # @return [void]
      def create_by_oauth
        auth = request.env["omniauth.auth"]
        if auth&.provider.to_s == "developer" && !Rails.env.development?
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions.oauth_unavailable"
                      )
          return
        end

        provider = OauthProvider.find_by(name: auth.provider) if auth.present?

        unless provider&.active?
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions.oauth_unavailable"
                      )
          return
        end

        account = UserOauthAccount.find_by(
          oauth_provider: provider,
          provider_uid: auth.uid
        )

        if account.nil?
          link_new_oauth_account(auth:, provider:)
        elsif current_principal &&
              account.principal != current_principal
          redirect_to authentication_destination(current_principal),
                      alert: t(
                        "vertiso.authentication.sessions." \
                        "oauth_account_linked_to_other_principal",
                        provider: provider.display_name
                      )
        elsif current_principal
          refresh_oauth_account_metadata(account:, auth:)
          redirect_to authentication_destination(current_principal),
                      notice: t(
                        "vertiso.authentication.sessions.oauth_already_linked",
                        provider: provider.display_name
                      )
        else
          sign_in_oauth_principal(account:, auth:)
        end
      end

      # Surfaces a provider callback failure.
      #
      # @return [void]
      def oauth_failure
        redirect_to login_path,
                    alert: t(
                      "vertiso.authentication.sessions.oauth_failure",
                      message: params[:message]
                    )
      end

      # Renders the email interstitial for a pending OAuth callback.
      #
      # @return [void]
      def prompt_email
        unless pending_oauth_valid?
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions." \
                        "oauth_email_session_expired"
                      )
          return
        end

        @typed_email = ""
      end

      # Completes a pending OAuth signup using an untrusted typed email.
      #
      # @return [void]
      def complete_email_signup
        @typed_email = params.expect(oauth_email: [:email])[:email]
                             .to_s.strip.downcase

        unless pending_oauth_valid?
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions." \
                        "oauth_email_session_expired"
                      )
          return
        end

        if @typed_email.blank? || !principal_class.valid_email?(@typed_email)
          flash.now[:alert] = t(
            "vertiso.authentication.sessions.email_invalid"
          )
          render :prompt_email, status: :unprocessable_content
          return
        end

        if principal_class.find_email(email: @typed_email)
          provider_name = pending_oauth_provider.display_name
          clear_pending_oauth
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions." \
                        "oauth_email_collision_untrusted",
                        provider: provider_name
                      )
          return
        end

        complete_pending_oauth_signup
      end

      # Logs out the current principal.
      #
      # @return [void]
      def destroy
        principal = current_principal
        log_out
        redirect_to logout_destination(principal),
                    status: :see_other,
                    notice: t("vertiso.authentication.sessions.signed_out")
      end

      private

      # Handles a provider identity that is not linked yet.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @return [void]
      def link_new_oauth_account(auth:, provider:)
        unless current_principal
          handle_anonymous_oauth_account(auth:, provider:)
          return
        end

        account = create_oauth_account_idempotently(
          principal: current_principal,
          auth:,
          provider:
        )
        unless account.principal == current_principal
          redirect_to authentication_destination(current_principal),
                      alert: t(
                        "vertiso.authentication.sessions." \
                        "oauth_account_linked_to_other_principal",
                        provider: provider.display_name
                      )
          return
        end

        redirect_to authentication_destination(current_principal),
                    notice: t(
                      "vertiso.authentication.sessions.oauth_linked",
                      provider: provider.display_name
                    )
      end

      # Applies the production trust and collision matrix anonymously.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @return [void]
      def handle_anonymous_oauth_account(auth:, provider:)
        email = auth.info.email.to_s
        if email.blank?
          stash_pending_oauth(auth:, provider:)
          redirect_to prompt_oauth_email_path,
                      notice: t(
                        "vertiso.authentication.sessions.oauth_email_needed",
                        provider: provider.display_name
                      )
          return
        end

        trusted = provider.email_trusted_for?(auth)
        principal = principal_class.find_email(email:)

        if principal.nil?
          create_oauth_principal(auth:, provider:, trusted:)
        elsif trusted
          link_oauth_to_existing_principal(
            principal:,
            auth:,
            provider:
          )
        else
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions." \
                        "oauth_email_collision_untrusted",
                        provider: provider.display_name
                      )
        end
      end

      # Links a trusted callback to an existing principal and signs it in.
      #
      # @param principal [ApplicationRecord]
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @return [void]
      def link_oauth_to_existing_principal(principal:, auth:, provider:)
        account = create_oauth_account_idempotently(
          principal:,
          auth:,
          provider:
        )
        sign_in_oauth_principal(account:, auth:)
      end

      # Signs in an existing linked identity owner.
      #
      # @param account [Vertiso::Authentication::UserOauthAccount]
      # @param auth [OmniAuth::AuthHash]
      # @return [void]
      def sign_in_oauth_principal(account:, auth:)
        refresh_oauth_account_metadata(account:, auth:)
        log_in(principal: account.principal)
        redirect_to authentication_destination(account.principal),
                    notice: t(
                      "vertiso.authentication.sessions.oauth_signed_in",
                      email: principal_email(account.principal)
                    )
      end

      # Replaces provider-owned profile and credential metadata.
      #
      # @param account [Vertiso::Authentication::UserOauthAccount]
      # @param auth [OmniAuth::AuthHash]
      # @return [void]
      def refresh_oauth_account_metadata(account:, auth:)
        account.update!(
          last_used_at: Time.current,
          email: auth.info.email,
          name: auth.info.name,
          user_info: auth.info.to_hash,
          user_credentials: auth.credentials.to_hash
        )
      end

      # Creates a linked account using only provider callback fields.
      #
      # @param principal [ApplicationRecord]
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @return [Vertiso::Authentication::UserOauthAccount]
      def create_oauth_account(principal:, auth:, provider:)
        principal.authentication_oauth_accounts.create!(
          oauth_provider: provider,
          provider_uid: auth.uid,
          email: auth.info.email,
          name: auth.info.name,
          user_info: auth.info.to_hash,
          user_credentials: auth.credentials.to_hash,
          last_used_at: Time.current
        )
      end

      # Creates a linked account or resolves the concurrent winner.
      #
      # @param principal [ApplicationRecord]
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @return [Vertiso::Authentication::UserOauthAccount]
      def create_oauth_account_idempotently(principal:, auth:, provider:)
        create_oauth_account(principal:, auth:, provider:)
      rescue ActiveRecord::RecordInvalid => error
        raise unless oauth_identity_uniqueness_failure?(
          error:,
          provider:,
          uid: auth.uid
        )

        oauth_identity_winner_or_raise(
          error:,
          provider:,
          uid: auth.uid
        )
      rescue ActiveRecord::RecordNotUnique => error
        oauth_identity_winner_or_raise(
          error:,
          provider:,
          uid: auth.uid
        )
      end

      # Creates an anonymous principal and linked account atomically.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @param trusted [Boolean]
      # @return [void]
      def create_oauth_principal(auth:, provider:, trusted:)
        principal = create_principal_with_oauth_account(
          auth:,
          provider:,
          email: auth.info.email,
          trusted:
        )

        unless principal.persisted?
          redirect_to login_path,
                      alert: t(
                        "vertiso.authentication.sessions.create_failed",
                        errors: principal.errors.full_messages.to_sentence
                      )
          return
        end

        log_in(principal:)
        if trusted
          redirect_to authentication_destination(principal),
                      notice: t(
                        "vertiso.authentication.sessions.oauth_signed_in",
                        email: principal_email(principal)
                      )
        else
          confirmation_flash = oauth_confirmation_flash(principal:)
          redirect_to confirmation_required_destination(principal),
                      **confirmation_flash
        end
      end

      # Completes the pending no-email flow with an untrusted email.
      #
      # @return [void]
      def complete_pending_oauth_signup
        pending = session[:pending_oauth]
        provider = OauthProvider.find(pending.fetch("provider_id"))
        auth = pending_oauth_auth_hash(pending:, email: @typed_email)
        principal = create_principal_with_oauth_account(
          auth:,
          provider:,
          email: @typed_email,
          trusted: false
        )

        unless principal.persisted?
          flash.now[:alert] = t(
            "vertiso.authentication.sessions.create_failed",
            errors: principal.errors.full_messages.to_sentence
          )
          render :prompt_email, status: :unprocessable_content
          return
        end

        clear_pending_oauth
        log_in(principal:)
        confirmation_flash = oauth_confirmation_flash(principal:)
        redirect_to confirmation_required_destination(principal),
                    **confirmation_flash
      end

      # Creates the principal and provider identity in one transaction.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @param email [String]
      # @param trusted [Boolean]
      # @return [ApplicationRecord]
      def create_principal_with_oauth_account(
        auth:,
        provider:,
        email:,
        trusted:
      )
        principal = principal_class.new(
          oauth_principal_attributes(
            auth:,
            email:,
            trusted:
          )
        )

        principal_class.transaction do
          principal.save!
          create_oauth_account(principal:, auth:, provider:)
        end
        principal
      rescue ActiveRecord::RecordInvalid => error
        if oauth_identity_uniqueness_failure?(
          error:,
          provider:,
          uid: auth.uid
        )
          return oauth_identity_winner_or_raise(
            error:,
            provider:,
            uid: auth.uid
          ).principal
        end

        copy_oauth_creation_errors(principal:, record: error.record)
        principal
      rescue ActiveRecord::RecordNotUnique => error
        oauth_identity_winner_or_raise(
          error:,
          provider:,
          uid: auth.uid
        ).principal
      end

      # Builds the host principal's allowlisted OAuth attributes.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param email [String]
      # @param trusted [Boolean]
      # @return [Hash]
      def oauth_principal_attributes(auth:, email:, trusted:)
        password = "Aa1!#{SecureRandom.alphanumeric(18)}"
        attributes_hook = authentication_configuration
                          .oauth_principal_attributes
        unless attributes_hook.respond_to?(:call)
          raise TypeError,
                "oauth_principal_attributes must be callable"
        end

        host_attributes = attributes_hook.call(auth:)
        unless host_attributes.is_a?(Hash)
          raise TypeError,
                "oauth_principal_attributes must return a Hash"
        end

        host_attributes.merge(
          authentication_configuration.email_attribute => email,
          authentication_configuration.user_name_attribute => oauth_user_name(
            auth:,
            email:
          ),
          authentication_configuration.email_confirmed_at_attribute =>
            (Time.current if trusted),
          password:,
          password_confirmation: password
        )
      end

      # Allocates the host principal's required unique user name.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param email [String]
      # @return [String]
      def oauth_user_name(auth:, email:)
        candidate = auth.info.nickname.to_s.presence ||
                    auth.info.name.to_s.presence ||
                    email.to_s.split("@").first.presence ||
                    "oauth-user"
        allocator = authentication_configuration.oauth_user_name_allocator
        unless allocator.respond_to?(:call)
          raise TypeError,
                "oauth_user_name_allocator must be callable"
        end

        allocated = allocator.call(
          principal_class:,
          candidate:
        )
        unless allocated.is_a?(String)
          raise TypeError,
                "oauth_user_name_allocator must return a String"
        end

        normalized = allocated.strip.downcase
        if normalized.blank?
          raise ArgumentError,
                "oauth_user_name_allocator must return a nonblank String"
        end

        normalized
      end

      # Copies second-write validation failures onto the returned principal.
      #
      # @param principal [ApplicationRecord]
      # @param record [ApplicationRecord]
      # @return [void]
      def copy_oauth_creation_errors(principal:, record:)
        return unless principal.errors.empty?

        record.errors.full_messages.each do |message|
          principal.errors.add(:base, message)
        end
      end

      # Returns whether a validation failure represents this identity race.
      #
      # @param error [ActiveRecord::RecordInvalid]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @param uid [String]
      # @return [Boolean]
      def oauth_identity_uniqueness_failure?(error:, provider:, uid:)
        record = error.record
        return false unless record.is_a?(UserOauthAccount)
        return false unless record.oauth_provider_id == provider.id
        return false unless record.provider_uid == uid

        record.errors.details.fetch(:provider_uid, []).any? do |detail|
          detail[:error] == :taken
        end
      end

      # Resolves the exact committed provider-identity winner.
      #
      # @param error [ActiveRecord::ActiveRecordError]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @param uid [String]
      # @return [Vertiso::Authentication::UserOauthAccount]
      # @raise [ActiveRecord::ActiveRecordError] when no exact winner exists
      def oauth_identity_winner_or_raise(error:, provider:, uid:)
        winner = UserOauthAccount.find_by(
          oauth_provider: provider,
          provider_uid: uid
        )
        raise error unless winner

        winner
      end

      # Stashes the callback fields needed for a delayed email completion.
      #
      # @param auth [OmniAuth::AuthHash]
      # @param provider [Vertiso::Authentication::OauthProvider]
      # @return [void]
      def stash_pending_oauth(auth:, provider:)
        session[:pending_oauth] = {
          "provider_id" => provider.id,
          "provider" => auth.provider,
          "uid" => auth.uid,
          "name" => auth.info.name,
          "nickname" => auth.info.nickname,
          "user_info" => auth.info.to_hash,
          "user_credentials" => auth.credentials.to_hash,
          "stashed_at" => Time.current.to_i
        }
      end

      # Returns whether a pending callback remains complete and unexpired.
      #
      # @return [Boolean]
      def pending_oauth_valid?
        pending = session[:pending_oauth]
        return false unless pending.is_a?(Hash)
        return false if pending["provider_id"].blank? || pending["uid"].blank?
        return false unless pending["stashed_at"].is_a?(Integer)

        age = Time.current.to_i - pending["stashed_at"]
        return false if age.negative? || age > PENDING_OAUTH_TTL.to_i

        OauthProvider.exists?(id: pending["provider_id"], active: true)
      end

      # Returns the active provider associated with the validated pending flow.
      #
      # @return [Vertiso::Authentication::OauthProvider]
      def pending_oauth_provider
        OauthProvider.find(session[:pending_oauth].fetch("provider_id"))
      end

      # Clears the delayed callback payload from the Rails session.
      #
      # @return [void]
      def clear_pending_oauth
        session.delete(:pending_oauth)
      end

      # Reconstructs an ordinary auth hash from pending callback fields.
      #
      # @param pending [Hash]
      # @param email [String]
      # @return [OmniAuth::AuthHash]
      def pending_oauth_auth_hash(pending:, email:)
        OmniAuth::AuthHash.new(
          provider: pending.fetch("provider"),
          uid: pending.fetch("uid"),
          info: pending.fetch("user_info").merge("email" => email),
          credentials: pending.fetch("user_credentials")
        )
      end

      # Returns the host principal class.
      #
      # @return [Class]
      def principal_class
        authentication_configuration.principal_class
      end

      # Enqueues confirmation for an untrusted OAuth-created principal.
      #
      # @param principal [ApplicationRecord]
      # @return [Hash]
      def oauth_confirmation_flash(principal:)
        dispatched = safely_dispatch(label: "ConfirmationOnOauthSignup") do
          AuthenticationMailer.confirm(principal).deliver_later
        end
        if dispatched
          {
            notice: t(
              "vertiso.authentication.sessions.confirm_oauth_email",
              email: principal_email(principal)
            )
          }
        else
          {
            alert: t(
              "vertiso.authentication.sessions." \
              "confirmation_dispatch_failed_oauth"
            )
          }
        end
      end

      # Returns the host's confirmation-required destination.
      #
      # @param principal [ApplicationRecord]
      # @return [String]
      def confirmation_required_destination(principal)
        configured_destination(
          authentication_configuration.confirmation_required_destination,
          principal
        )
      end

      # @param principal [ApplicationRecord]
      # @return [void]
      def complete_login(principal:)
        log_in(principal:)
        destination = recall_location || authentication_destination(principal)
        redirect_to destination,
                    notice: t("vertiso.authentication.sessions.signed_in")
      end

      # @param principal [ApplicationRecord, nil]
      # @return [String]
      def authentication_destination(principal)
        configured_destination(
          authentication_configuration.post_authentication_destination,
          principal
        )
      end

      # @param principal [ApplicationRecord, nil]
      # @return [String]
      def logout_destination(principal)
        configured_destination(
          authentication_configuration.post_logout_destination,
          principal
        )
      end

      # @param callable [Proc, nil]
      # @param principal [ApplicationRecord, nil]
      # @return [String]
      def configured_destination(callable, principal)
        return callable.call(self, principal) if callable

        main_app.root_path
      end

      # @return [Vertiso::Authentication::Configuration]
      def authentication_configuration
        Vertiso::Authentication.configuration
      end

      # Returns the configured principal email.
      #
      # @param principal [ApplicationRecord]
      # @return [String]
      def principal_email(principal)
        principal.public_send(authentication_configuration.email_attribute)
      end
    end
  end
end
