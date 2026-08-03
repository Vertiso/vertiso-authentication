# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "omniauth"

class VertisoAuthenticationOauthSessionsMappedControllerTest < ActionDispatch::IntegrationTest
  CALLBACK_PATH = "/authentication/auth/google_oauth2/callback"

  setup do
    skip "requires the mapped dummy host" unless User.attribute_names.include?(
      "handle"
    )

    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
      config.post_authentication_destination = lambda do |controller, principal|
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
      config.oauth_user_name_allocator = lambda do |principal_class:, candidate:|
        normalized = candidate.to_s.strip.downcase
        next normalized unless principal_class.exists?(handle: normalized)

        "#{normalized}-#{SecureRandom.alphanumeric(6).downcase}"
      end
    end
    @provider = Vertiso::Authentication::OauthProvider.create!(
      name: "google_oauth2",
      display_name: "Google",
      trusts_email: true
    )
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "OAuth principal creation uses mapped handle and confirmation fields" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "mapped-oauth",
      info: {
        email: "mapped@example.com",
        name: "Mapped OAuth",
        nickname: "mapped-user"
      },
      credentials: {
        token: "mapped-token"
      }
    )

    freeze_time do
      get CALLBACK_PATH, env: { "omniauth.auth" => auth }

      principal = User.find_by!(email: "mapped@example.com")

      assert_redirected_to(
        "/signed-in?principal_id=#{principal.id}&source=oauth"
      )
      assert_equal "mapped-user", principal.handle
      assert_equal "Mapped OAuth", principal.name
      assert_equal Time.current, principal.email_confirmed_at
    end
  end
end
