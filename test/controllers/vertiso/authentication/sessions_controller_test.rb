# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationSessionsControllerTest < ActionDispatch::IntegrationTest
  LOGIN_PATH = "/authentication/login"
  LOGOUT_PATH = "/authentication/logout"
  STATE_PATH = "/authentication-state"
  PASSWORD = "TestPassword1234!"

  setup do
    configure_host
    @principal = create_principal
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "login route renders the extracted authentication components" do
    Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      active: true,
      trusts_email: true
    )

    get LOGIN_PATH

    assert_response :success
    assert_select "main[aria-labelledby='vertiso-auth-title']"
    assert_select "form[action='/authentication/login']"
    assert_select "form[action='/auth/google_oauth2']"
    assert_select "input[autocomplete='username'][required]"
    assert_select "input[autocomplete='current-password'][required]"
  end

  test "logs in by normalized email" do
    post LOGIN_PATH, params: {
      session: {
        login: " PERSON@EXAMPLE.COM ",
        password: PASSWORD
      }
    }

    assert_redirected_to "/signed-in?principal_id=#{@principal.id}"

    get STATE_PATH

    assert_equal @principal.id, response.parsed_body.fetch("principal_id")
  end

  test "logs in by normalized user name" do
    post LOGIN_PATH, params: {
      session: {
        login: " PERSON ",
        password: PASSWORD
      }
    }

    assert_redirected_to "/signed-in?principal_id=#{@principal.id}"
  end

  test "invalid login renders unprocessable content" do
    post LOGIN_PATH, params: {
      session: {
        login: "person@example.com",
        password: "WrongPassword1234!"
      }
    }

    assert_response :unprocessable_content
    assert_nil cookies[:remember_token]
    assert_equal 0, Vertiso::Authentication::AuthenticationSession.count
  end

  test "successful login resets Rails session and writes an encrypted persistent cookie" do
    get "/seed-session"
    old_identifier = response.parsed_body.fetch("session_identifier")

    post LOGIN_PATH,
         params: {
           session: {
             login: "person@example.com",
             password: PASSWORD
           }
         },
         headers: { "User-Agent" => "Vertiso Authentication Request Test" }

    raw_cookie = cookies[:remember_token]
    assert_predicate raw_cookie, :present?
    set_cookie_headers = Array(response.headers.fetch("Set-Cookie")).join("\n")
    assert_match(/expires=/i, set_cookie_headers)

    get STATE_PATH
    state = response.parsed_body
    token = state.fetch("remember_token")

    assert_nil state["stale_marker"]
    assert_not_equal old_identifier, state.fetch("session_identifier")
    assert_not_equal token, raw_cookie
    assert_equal @principal,
                 User.find_by_token_for(:remember_token, token)
  end

  test "uses the configured encrypted cookie key while preserving the Rails session token key" do
    Vertiso::Authentication.configuration.remember_cookie_key = :browser_credential

    post LOGIN_PATH, params: {
      session: {
        login: "person@example.com",
        password: PASSWORD
      }
    }

    assert_nil cookies[:remember_token]
    assert_predicate cookies[:browser_credential], :present?

    get STATE_PATH

    assert_predicate response.parsed_body.fetch("remember_token"), :present?
    assert_equal @principal.id, response.parsed_body.fetch("principal_id")
  end

  test "logout resets Rails session, expires metadata, and clears the cookie" do
    post_login
    authentication_session = Vertiso::Authentication::AuthenticationSession.find_by!(
      principal: @principal
    )
    previous_identifier = authentication_session.session_identifier

    travel 5.minutes do
      delete LOGOUT_PATH

      assert_redirected_to "/signed-in?logged_out=1"
      assert_predicate cookies[:remember_token], :blank?
      assert_equal Time.current, authentication_session.reload.expires_at

      get STATE_PATH
      state = response.parsed_body

      assert_nil state["principal_id"]
      assert_nil state["remember_token"]
      assert_not_equal previous_identifier, state.fetch("session_identifier")
    end
  end

  test "invalid remember token clears the cookie" do
    post_login
    delete "/session-token"
    @principal.reset_session_token!

    get STATE_PATH

    assert_nil response.parsed_body["principal_id"]
    assert_predicate cookies[:remember_token], :blank?
  end

  test "expired remember token clears the cookie" do
    post_login
    delete "/session-token"

    travel 31.days do
      get STATE_PATH

      assert_nil response.parsed_body["principal_id"]
      assert_predicate cookies[:remember_token], :blank?
    end
  end

  test "saved return location survives login and becomes a same-origin relative path" do
    get "/resume", params: { source: "saved" }

    assert_redirected_to LOGIN_PATH

    post LOGIN_PATH, params: {
      session: {
        login: "person@example.com",
        password: PASSWORD
      }
    }

    assert_redirected_to "/resume?source=saved"
  end

  test "recalls only safe relative or same-host absolute continuations" do
    safe_locations = {
      "ordinary relative path" => [
        "/path?query=value",
        "/path?query=value"
      ],
      "same-host absolute URL" => [
        "https://www.example.com/path?query=value",
        "/path?query=value"
      ]
    }

    safe_locations.each do |label, (stored_location, expected_location)|
      assert_saved_location_redirect(
        stored_location:,
        expected_location:,
        message: label
      )
    end
  end

  test "rejects unsafe or malformed saved continuations without raising" do
    unsafe_locations = {
      "scheme-relative host" => "//evil.example/path",
      "percent-decoded double slash" => "/%2Fevil.example/path",
      "raw backslash" => "/\\evil.example/path",
      "percent-encoded backslash" => "/%5Cevil.example/path",
      "raw carriage return and line feed" => "/path\r\nX-Test: injected",
      "percent-encoded carriage return and line feed" => "/path%0D%0AX-Test%3A%20injected",
      "opaque URI" => "mailto:person@example.com",
      "non-HTTP URI" => "ftp://www.example.com/path",
      "malformed percent escape" => "/path%2",
      "invalid percent encoding" => "/%FF",
      "external absolute URL" => "https://attacker.example/path?query=value",
      "missing path" => "https://www.example.com",
      "relative path without leading slash" => "relative/path"
    }

    unsafe_locations.each do |label, stored_location|
      assert_saved_location_redirect(
        stored_location:,
        expected_location: signed_in_location,
        message: label
      )
    end
  end

  test "a real double-slash GET cannot break the successful login redirect" do
    get "//resume"

    assert_redirected_to LOGIN_PATH

    post_login

    assert_redirected_to signed_in_location
  end

  test "unexpected continuation validation errors are not swallowed" do
    controller_class = Class.new do
      include Vertiso::Authentication::BrowserAuthentication

      # @return [Hash]
      def session
        { forward_to_url: "/path" }
      end

      private

      # @return [void]
      def safe_continuation_location(url:)
        raise RuntimeError, "unexpected continuation validator failure: #{url}"
      end
    end

    error = assert_raises(RuntimeError) do
      controller_class.new.recall_location
    end

    assert_equal "unexpected continuation validator failure: /path",
                 error.message
  end

  test "login creates one active metadata record keyed by the Rails session public identifier" do
    freeze_time do
      assert_difference(
        -> { Vertiso::Authentication::AuthenticationSession.count },
        1
      ) do
        post LOGIN_PATH,
             params: {
               session: {
                 login: "person@example.com",
                 password: PASSWORD
               }
             },
             headers: { "User-Agent" => "Vertiso Authentication Request Test" }
      end

      authentication_session = Vertiso::Authentication::AuthenticationSession.find_by!(
        principal: @principal
      )

      get STATE_PATH

      assert_equal response.parsed_body.fetch("session_identifier"),
                   authentication_session.session_identifier
      assert_equal "Vertiso Authentication Request Test",
                   authentication_session.user_agent
      assert_predicate authentication_session.ip_address, :present?
      assert_equal Time.current, authentication_session.last_activity_at
      assert_equal 30.days.from_now, authentication_session.expires_at
      assert_predicate authentication_session, :active?
    end
  end

  test "an authenticated request updates metadata activity" do
    freeze_time do
      post_login
      authentication_session = Vertiso::Authentication::AuthenticationSession.find_by!(
        principal: @principal
      )

      travel 10.minutes
      get STATE_PATH

      assert_equal @principal.id, response.parsed_body.fetch("principal_id")
      assert_equal Time.current,
                   authentication_session.reload.last_activity_at
    end
  end

  test "deleting metadata leaves remember token resolution unchanged" do
    post_login
    Vertiso::Authentication::AuthenticationSession.find_by!(
      principal: @principal
    ).destroy!

    get STATE_PATH

    assert_equal @principal.id, response.parsed_body.fetch("principal_id")
  end

  test "expiring metadata leaves remember token resolution unchanged" do
    post_login
    authentication_session = Vertiso::Authentication::AuthenticationSession.find_by!(
      principal: @principal
    )
    authentication_session.update!(expires_at: 1.minute.ago)

    get STATE_PATH

    assert_equal @principal.id, response.parsed_body.fetch("principal_id")
    assert_not_predicate authentication_session.reload, :active?
  end

  private

  def configure_host
    Vertiso::Authentication.reset_configuration!
    Vertiso::Authentication.configure do |config|
      if mapped_host?
        config.user_name_attribute = :handle
        config.email_confirmed_at_attribute = :email_confirmed_at
      end
      config.post_authentication_destination = lambda do |controller, principal|
        controller.main_app.signed_in_path(principal_id: principal.id)
      end
      config.post_logout_destination = lambda do |controller, _principal|
        controller.main_app.signed_in_path(logged_out: 1)
      end
    end
  end

  def create_principal
    attributes = {
      email: "person@example.com",
      password: PASSWORD,
      password_confirmation: PASSWORD,
      Vertiso::Authentication.configuration.user_name_attribute => "person"
    }

    User.create!(attributes)
  end

  def mapped_host?
    ENV.fetch("DUMMY_APP", "dummy_standard") == "dummy_mapped"
  end

  def post_login
    post LOGIN_PATH, params: {
      session: {
        login: "person@example.com",
        password: PASSWORD
      }
    }
  end

  def assert_saved_location_redirect(stored_location:, expected_location:, message:)
    browser = open_session
    browser.get "/seed-session", params: { forward_to_url: stored_location }
    assert_equal 200, browser.response.status, message

    browser.post LOGIN_PATH, params: {
      session: {
        login: "person@example.com",
        password: PASSWORD
      }
    }

    assert_equal 302, browser.response.status, message
    assert_equal absolute_url(expected_location), browser.response.location, message
  end

  def absolute_url(path)
    "http://www.example.com#{path}"
  end

  def signed_in_location
    "/signed-in?principal_id=#{@principal.id}"
  end
end
