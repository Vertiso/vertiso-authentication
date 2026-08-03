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
      release_validation << true if release_validation&.empty?
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
