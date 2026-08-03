# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationRegistrationsControllerTest < ActionDispatch::IntegrationTest
  REGISTRATION_PATH = "/authentication/register"
  STATE_PATH = "/authentication-state"
  PASSWORD = "TestPassword1234!"

  setup do
    Vertiso::Authentication.reset_configuration!
    Vertiso::Authentication.configure do |config|
      if mapped_host?
        config.user_name_attribute = :handle
        config.email_confirmed_at_attribute = :email_confirmed_at
      end
      config.post_registration_destination = lambda do |controller, principal|
        controller.main_app.registered_path(principal_id: principal.id)
      end
    end
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "registration maps production authentication fields and logs in the principal" do
    assert_difference(-> { User.count }, 1) do
      post REGISTRATION_PATH, params: {
        registration: {
          email: " NEW@EXAMPLE.COM ",
          user_name: " NewPerson ",
          password: PASSWORD,
          password_confirmation: PASSWORD,
          name: "Profile field must stay host-owned",
          admin: true
        }
      }
    end

    principal = User.find_by!(
      Vertiso::Authentication.configuration.email_attribute => "new@example.com"
    )
    user_name_attribute = Vertiso::Authentication.configuration.user_name_attribute

    assert_equal "newperson", principal.public_send(user_name_attribute)
    assert_redirected_to "/registered?principal_id=#{principal.id}"

    get STATE_PATH
    token = response.parsed_body.fetch("remember_token")

    assert_equal principal,
                 User.find_by_token_for(:remember_token, token)
    assert Vertiso::Authentication::AuthenticationSession.exists?(principal:)
  end

  test "invalid registration renders unprocessable content without logging in" do
    assert_no_difference(-> { User.count }) do
      post REGISTRATION_PATH, params: {
        registration: {
          email: "invalid@example.com",
          user_name: "invalid",
          password: "weak",
          password_confirmation: "weak"
        }
      }
    end

    assert_response :unprocessable_content
    assert_nil cookies[:remember_token]
    assert_equal 0, Vertiso::Authentication::AuthenticationSession.count
  end

  private

  def mapped_host?
    ENV.fetch("DUMMY_APP", "dummy_standard") == "dummy_mapped"
  end
end
