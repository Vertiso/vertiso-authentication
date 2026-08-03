# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationMappedAuthenticatableTest < ActiveSupport::TestCase
  setup do
    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "authenticates a mapped principal by email or handle" do
    user = User.create!(
      email: " Person@Example.com ",
      handle: " Person ",
      password: "TestPassword1234!"
    )

    assert_equal "person@example.com", user.email
    assert_equal "person", user.handle
    assert user.authenticate("TestPassword1234!")
    assert_equal user, User.find_login("person@example.com")
    assert_equal user, User.find_login("PERSON")
    assert_nil user.email_confirmed_at
  end

  test "rejects duplicate handles regardless of case" do
    User.create!(
      email: "person@example.com",
      handle: "person",
      password: "TestPassword1234!"
    )
    duplicate = User.new(
      email: "other@example.com",
      handle: "PERSON",
      password: "TestPassword1234!"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:handle], "has already been taken"
  end
end
