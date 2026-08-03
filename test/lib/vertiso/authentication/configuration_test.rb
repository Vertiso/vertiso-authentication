# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationConfigurationTest < ActiveSupport::TestCase
  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "uses the conventional principal defaults" do
    configuration = Vertiso::Authentication::Configuration.new

    assert_equal "User", configuration.principal_class_name
    assert_equal :email, configuration.email_attribute
    assert_equal :user_name, configuration.user_name_attribute
    assert_equal :email_verified_at, configuration.email_confirmed_at_attribute
    assert_equal 30.days, configuration.remember_token_lifetime
    assert_equal 24.hours, configuration.email_confirmation_lifetime
    assert_equal 1.hour, configuration.password_reset_lifetime
    assert_equal 30.days, configuration.authentication_session_lifetime
  end

  test "accepts alternate host attribute names" do
    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end

    assert_equal :handle,
                 Vertiso::Authentication.configuration.user_name_attribute
    assert_equal :email_confirmed_at,
                 Vertiso::Authentication.configuration.email_confirmed_at_attribute
  end

  test "resets configured values" do
    Vertiso::Authentication.configure do |config|
      config.principal_class_name = "AlternateUser"
    end

    Vertiso::Authentication.reset_configuration!

    assert_equal "User", Vertiso::Authentication.configuration.principal_class_name
  end

  test "resolves the configured principal only when requested" do
    Vertiso::Authentication.configure do |config|
      config.principal_class_name = "MissingPrincipal"
    end

    assert_raises NameError do
      Vertiso::Authentication.configuration.principal_class
    end
  end
end
