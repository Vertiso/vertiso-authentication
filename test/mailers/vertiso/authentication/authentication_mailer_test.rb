# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

# Exercises configured confirmation and password-reset message generation.
class VertisoAuthenticationAuthenticationMailerTest < ActionMailer::TestCase
  PASSWORD = "TestPassword1234!"

  setup do
    configure_host
    @principal = create_principal
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "confirmation resolves sender host and URL options and uses the production token purpose" do
    mail = Vertiso::Authentication::AuthenticationMailer.confirm(@principal)
    html = mail.html_part.body.decoded
    text = mail.text_part.body.decoded
    token = html[%r{/mounted-auth/confirm-email/([^"<\s]+)}, 1]
    expected_url = "https://auth.example.test/mounted-auth/confirm-email/#{token}"

    assert_equal ["person@example.com"], mail.to
    assert_equal ["authentication@example.test"], mail.from
    assert_equal I18n.t("vertiso.authentication.mailer.confirmation.subject"),
                 mail.subject
    assert_includes html, expected_url
    assert_includes text, expected_url
    assert_equal @principal,
                 User.find_by_token_for(:email_verification, token)
  end

  test "reset preserves the caller-generated token in both message parts" do
    token = @principal.generate_token_for(:password_reset)
    mail = Vertiso::Authentication::AuthenticationMailer.reset(
      @principal,
      token
    )
    expected_url = "https://auth.example.test/mounted-auth/reset-password/#{token}"

    assert_equal ["person@example.com"], mail.to
    assert_equal ["authentication@example.test"], mail.from
    assert_equal I18n.t("vertiso.authentication.mailer.password_reset.subject"),
                 mail.subject
    assert_includes mail.html_part.body.decoded, expected_url
    assert_includes mail.text_part.body.decoded, expected_url
    assert_equal @principal,
                 User.find_by_token_for(:password_reset, token)
  end

  private

  def configure_host
    Vertiso::Authentication.reset_configuration!
    Vertiso::Authentication.configure do |config|
      if mapped_host?
        config.user_name_attribute = :handle
        config.email_confirmed_at_attribute = :email_confirmed_at
      end
      config.mailer_sender = -> { "authentication@example.test" }
      config.mailer_host = -> { "auth.example.test" }
      config.mailer_url_options = lambda do
        {
          protocol: "https",
          script_name: "/mounted-auth"
        }
      end
    end
  end

  def create_principal
    User.create!(
      email: "person@example.com",
      Vertiso::Authentication.configuration.user_name_attribute => "person",
      password: PASSWORD,
      password_confirmation: PASSWORD
    )
  end

  def mapped_host?
    ENV.fetch("DUMMY_APP", "dummy_standard") == "dummy_mapped"
  end
end
