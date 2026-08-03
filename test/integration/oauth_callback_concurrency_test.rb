# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "open3"
require "rbconfig"
require "tmpdir"
require "test_helper"

if ENV["VAUTH_CONCURRENCY_WORKER"] == "1"
  # Exercises callback races against a file-backed database with real connections.
  class VertisoAuthenticationOauthCallbackConcurrencyWorkerTest <
    ActionDispatch::IntegrationTest
    CALLBACK_PATH = "/authentication/auth/google_oauth2/callback"
    LOGIN_PATH = "/authentication/login"
    PASSWORD = "TestPassword1234!"

    self.use_transactional_tests = false

    setup do
      @show_exceptions =
        Rails.application.env_config["action_dispatch.show_exceptions"]
      Rails.application.env_config["action_dispatch.show_exceptions"] = :none
      configure_database
      configure_host
      clear_authentication_records
    end

    teardown do
      Rails.application.env_config["action_dispatch.show_exceptions"] =
        @show_exceptions
      Vertiso::Authentication.reset_configuration!
      clear_authentication_records
    end

    test "concurrent callbacks resolve the committed provider identity winner" do
      provider = Vertiso::Authentication::OauthProvider.create!(
        name: "google_oauth2",
        display_name: "Google",
        trusts_email: true
      )
      principal = User.create!(
        email: "owner@example.com",
        user_name: "owner",
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
      loser = signed_in_session(principal:)
      winner = signed_in_session(principal:)
      entered_validation = Queue.new
      release_validation = Queue.new
      observed_collision = Queue.new
      target_uid = "concurrent-provider-identity"

      install_race_barrier(
        target_uid:,
        entered_validation:,
        release_validation:,
        observed_collision:
      )

      loser_thread = callback_thread(
        session: loser,
        role: :loser,
        target_uid:
      )
      entered_validation.pop
      winner_thread = callback_thread(
        session: winner,
        role: :winner,
        target_uid:
      )
      winner_result = winner_thread.value
      release_validation << true
      loser_result = loser_thread.value

      expected_location = oauth_destination(principal)
      assert_equal(
        302,
        winner_result.fetch(:status),
        winner_result.fetch(:body)
      )
      assert_equal expected_location, winner_result.fetch(:location)
      assert_equal 302, loser_result.fetch(:status)
      assert_equal expected_location, loser_result.fetch(:location)
      assert_equal :taken, observed_collision.pop
      assert_equal 1, User.count
      assert_equal 1,
                   Vertiso::Authentication::UserOauthAccount.where(
                     oauth_provider: provider,
                     provider_uid: target_uid
                   ).count
      assert_equal(
        principal,
        Vertiso::Authentication::UserOauthAccount.find_by!(
          oauth_provider: provider,
          provider_uid: target_uid
        ).principal
      )
    ensure
      release_validation << true if release_validation && release_validation.empty?
      remove_race_barrier
      loser_thread&.join
      winner_thread&.join
    end

    test "anonymous callbacks resolve a principal-validation race winner" do
      provider = Vertiso::Authentication::OauthProvider.create!(
        name: "google_oauth2",
        display_name: "Google",
        trusts_email: true
      )
      loser = ActionDispatch::Integration::Session.new(Rails.application)
      winner = ActionDispatch::Integration::Session.new(Rails.application)
      entered_validation = Queue.new
      release_validation = Queue.new
      observed_collision = Queue.new
      account_validation = Queue.new
      target_uid = "anonymous-concurrent-provider-identity"

      install_principal_race_barrier(
        entered_validation:,
        release_validation:,
        observed_collision:,
        account_validation:
      )

      loser_thread = callback_thread(
        session: loser,
        role: :loser,
        target_uid:
      )
      entered_validation.pop
      winner_thread = callback_thread(
        session: winner,
        role: :winner,
        target_uid:
      )
      winner_result = winner_thread.value
      release_validation << true
      loser_result = loser_thread.value

      account = Vertiso::Authentication::UserOauthAccount.find_by!(
        oauth_provider: provider,
        provider_uid: target_uid
      )
      principal = account.principal
      expected_location = oauth_destination(principal)
      assert_equal 302, winner_result.fetch(:status)
      assert_equal expected_location, winner_result.fetch(:location)
      assert_equal 302, loser_result.fetch(:status)
      assert_equal expected_location, loser_result.fetch(:location)
      assert_includes observed_collision.pop, [:email, :taken]
      assert_predicate account_validation, :empty?
      assert_equal 1, User.count
      assert_equal 1, Vertiso::Authentication::UserOauthAccount.count
      assert_equal principal.id, current_principal_id(session: winner)
      assert_equal principal.id, current_principal_id(session: loser)
    ensure
      release_validation << true if release_validation && release_validation.empty?
      remove_principal_race_barrier
      loser_thread&.join
      winner_thread&.join
    end

    test "different signed-in principals keep their owners after race recovery" do
      provider = Vertiso::Authentication::OauthProvider.create!(
        name: "google_oauth2",
        display_name: "Google",
        trusts_email: true
      )
      loser_principal = User.create!(
        email: "loser-owner@example.com",
        user_name: "loser-owner",
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
      winner_principal = User.create!(
        email: "winner-owner@example.com",
        user_name: "winner-owner",
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
      loser = signed_in_session(principal: loser_principal)
      winner = signed_in_session(principal: winner_principal)
      entered_validation = Queue.new
      release_validation = Queue.new
      observed_collision = Queue.new
      target_uid = "different-owner-provider-identity"

      install_race_barrier(
        target_uid:,
        entered_validation:,
        release_validation:,
        observed_collision:
      )

      loser_thread = callback_thread(
        session: loser,
        role: :loser,
        target_uid:
      )
      entered_validation.pop
      winner_thread = callback_thread(
        session: winner,
        role: :winner,
        target_uid:
      )
      winner_result = winner_thread.value
      release_validation << true
      loser_result = loser_thread.value

      assert_equal oauth_destination(winner_principal),
                   winner_result.fetch(:location)
      assert_equal oauth_destination(loser_principal),
                   loser_result.fetch(:location)
      assert_equal :taken, observed_collision.pop
      assert_equal(
        winner_principal,
        Vertiso::Authentication::UserOauthAccount.find_by!(
          oauth_provider: provider,
          provider_uid: target_uid
        ).principal
      )
      assert_equal loser_principal.id,
                   current_principal_id(session: loser)
      assert_equal winner_principal.id,
                   current_principal_id(session: winner)
      assert_equal 2, User.count
      assert_equal 1, Vertiso::Authentication::UserOauthAccount.count
    ensure
      release_validation << true if release_validation && release_validation.empty?
      remove_race_barrier
      loser_thread&.join
      winner_thread&.join
    end

    private

    # Runs one callback in an isolated database connection.
    #
    # @param session [ActionDispatch::Integration::Session]
    # @param role [Symbol]
    # @param target_uid [String]
    # @return [Thread]
    def callback_thread(session:, role:, target_uid:)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Thread.current[:vauth_oauth_race_role] = role
          session.get(
            CALLBACK_PATH,
            env: {
              "omniauth.auth" => oauth_auth(uid: target_uid)
            }
          )
          {
            status: session.response.status,
            location: session.response.location,
            body: session.response.body
          }
        ensure
          Thread.current[:vauth_oauth_race_role] = nil
        end
      end
    end

    # Removes records in foreign-key order.
    #
    # @return [void]
    def clear_authentication_records
      Vertiso::Authentication::AuthenticationSession.delete_all
      Vertiso::Authentication::UserOauthAccount.delete_all
      Vertiso::Authentication::OauthProvider.delete_all
      User.delete_all
    end

    # Enables SQLite concurrency behavior used by the callback race.
    #
    # @return [void]
    def configure_database
      connection = ActiveRecord::Base.connection
      connection.execute("PRAGMA journal_mode = WAL")
      connection.execute("PRAGMA busy_timeout = 5000")
    end

    # Configures the required host-owned OAuth contracts.
    #
    # @return [void]
    def configure_host
      Vertiso::Authentication.reset_configuration!
      Vertiso::Authentication.configure do |config|
        config.post_authentication_destination =
          lambda do |controller, principal|
            controller.main_app.signed_in_path(
              principal_id: principal.id,
              source: "oauth"
            )
          end
        config.oauth_principal_attributes = lambda do |auth:|
          {
            name: auth.info.name.to_s.presence || "OAuth User"
          }
        end
        config.oauth_user_name_allocator =
          lambda do |principal_class:, candidate:|
            normalized = candidate.to_s.strip.downcase
            next normalized unless principal_class.exists?(
              user_name: normalized
            )

            "#{normalized}-#{SecureRandom.alphanumeric(6).downcase}"
          end
      end
    end

    # Installs a validation barrier after the callback's identity lookup.
    #
    # @param target_uid [String]
    # @param entered_validation [Queue]
    # @param release_validation [Queue]
    # @param observed_collision [Queue]
    # @return [void]
    def install_race_barrier(
      target_uid:,
      entered_validation:,
      release_validation:,
      observed_collision:
    )
      before_validation = lambda do |account|
        next unless account.provider_uid == target_uid
        next unless Thread.current[:vauth_oauth_race_role] == :loser

        entered_validation << true
        release_validation.pop
      end
      after_validation = lambda do |account|
        next unless account.provider_uid == target_uid
        next unless Thread.current[:vauth_oauth_race_role] == :loser

        detail = account.errors.details.fetch(:provider_uid, []).find do |error|
          error[:error] == :taken
        end
        observed_collision << detail.fetch(:error) if detail
      end
      @race_callbacks = {
        before: before_validation,
        after: after_validation
      }
      @race_callbacks.each do |kind, callback|
        Vertiso::Authentication::UserOauthAccount.set_callback(
          :validation,
          kind,
          callback
        )
      end
    end

    # Installs a principal-validation race before linked-account validation.
    #
    # @param entered_validation [Queue]
    # @param release_validation [Queue]
    # @param observed_collision [Queue]
    # @param account_validation [Queue]
    # @return [void]
    def install_principal_race_barrier(
      entered_validation:,
      release_validation:,
      observed_collision:,
      account_validation:
    )
      before_principal_validation = lambda do
        next unless Thread.current[:vauth_oauth_race_role] == :loser

        entered_validation << true
        release_validation.pop
      end
      after_principal_validation = lambda do |principal|
        next unless Thread.current[:vauth_oauth_race_role] == :loser

        collisions = %i[email user_name].filter_map do |attribute|
          detail = principal.errors.details.fetch(attribute, []).find do |error|
            error[:error] == :taken
          end
          [attribute, detail[:error]] if detail
        end
        observed_collision << collisions if collisions.any?
      end
      before_account_validation = lambda do
        next unless Thread.current[:vauth_oauth_race_role] == :loser

        account_validation << true
      end
      @principal_race_callbacks = [
        [User, :validation, :before, before_principal_validation],
        [User, :validation, :after, after_principal_validation],
        [
          Vertiso::Authentication::UserOauthAccount,
          :validation,
          :before,
          before_account_validation
        ]
      ]
      @principal_race_callbacks.each do |klass, lifecycle, kind, callback|
        klass.set_callback(lifecycle, kind, callback)
      end
    end

    # Removes the validation barrier when installed.
    #
    # @return [void]
    def remove_race_barrier
      return unless @race_callbacks

      @race_callbacks.each do |kind, callback|
        Vertiso::Authentication::UserOauthAccount.skip_callback(
          :validation,
          kind,
          callback
        )
      end
      @race_callbacks = nil
    rescue ArgumentError
      nil
    end

    # Removes the principal-validation race callbacks when installed.
    #
    # @return [void]
    def remove_principal_race_barrier
      return unless @principal_race_callbacks

      @principal_race_callbacks.each do |klass, lifecycle, kind, callback|
        klass.skip_callback(lifecycle, kind, callback)
      end
      @principal_race_callbacks = nil
    rescue ArgumentError
      nil
    end

    # Builds the provider callback payload used by each request.
    #
    # @param uid [String]
    # @return [OmniAuth::AuthHash]
    def oauth_auth(uid:)
      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid:,
        info: {
          email: "provider@example.com",
          name: "Provider User",
          nickname: "provider-user"
        },
        credentials: {
          token: "callback-token"
        }
      )
    end

    # Returns the configured host destination for a principal.
    #
    # @param principal [User]
    # @return [String]
    def oauth_destination(principal)
      "http://www.example.com/signed-in?" \
        "principal_id=#{principal.id}&source=oauth"
    end

    # Returns the host-visible current principal for a browser session.
    #
    # @param session [ActionDispatch::Integration::Session]
    # @return [Integer, nil]
    def current_principal_id(session:)
      session.get("/authentication-state")
      session.response.parsed_body["principal_id"]
    end

    # Creates an independent browser session signed into the same principal.
    #
    # @param principal [User]
    # @return [ActionDispatch::Integration::Session]
    def signed_in_session(principal:)
      integration_session =
        ActionDispatch::Integration::Session.new(Rails.application)
      integration_session.post(
        LOGIN_PATH,
        params: {
          session: {
            login: principal.email,
            password: PASSWORD
          }
        }
      )
      assert_equal 302, integration_session.response.status
      integration_session
    end
  end
else
  # Launches the concurrency test with a shared, file-backed SQLite database.
  class VertisoAuthenticationOauthCallbackConcurrencyTest <
    ActiveSupport::TestCase
    test "callback race is recovered against a real unique constraint" do
      Dir.mktmpdir("vertiso-authentication-oauth-race") do |directory|
        database_path = File.join(directory, "oauth-race.sqlite3")
        environment = {
          "DATABASE_URL" => "sqlite3:#{database_path}",
          "DUMMY_APP" => "dummy_standard",
          "RAILS_ENV" => "test",
          "VAUTH_CONCURRENCY_WORKER" => "1"
        }
        stdout, stderr, status = Open3.capture3(
          environment,
          RbConfig.ruby,
          "-Itest",
          __FILE__,
          chdir: File.expand_path("../..", __dir__)
        )

        assert status.success?, "#{stdout}\n#{stderr}"
      end
    end
  end
end
