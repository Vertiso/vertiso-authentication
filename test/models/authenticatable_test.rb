# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationAuthenticatableTest < ActiveSupport::TestCase
  test "including the concern applies secure password authentication" do
    user = User.create!(
      email: "person@example.com",
      user_name: "person",
      password: "TestPassword1234!",
      password_confirmation: "TestPassword1234!"
    )

    assert user.authenticate("TestPassword1234!")
    assert_not user.authenticate("WrongPassword1234!")
  end

  test "normalizes and finds a principal by email or user name" do
    user = User.create!(
      email: " Person@Example.com ",
      user_name: " Person ",
      password: "TestPassword1234!"
    )

    assert_equal "person@example.com", user.email
    assert_equal "person", user.user_name
    assert_equal user, User.find_login("person@example.com")
    assert_equal user, User.find_login("PERSON")
    assert_equal user, User.find_email(email: " PERSON@example.com ")
  end

  test "rejects duplicate identity fields regardless of case" do
    User.create!(
      email: "person@example.com",
      user_name: "person",
      password: "TestPassword1234!"
    )
    duplicate = User.new(
      email: "PERSON@example.com",
      user_name: "PERSON",
      password: "TestPassword1234!"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
    assert_includes duplicate.errors[:user_name], "has already been taken"
  end

  test "enforces the Vertiso Memory password policy" do
    user = User.new(email: "person@example.com", user_name: "person")

    user.password = "A1!"

    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)

    user.password = "longenoughpassword1!"

    assert_not user.valid?
    assert user.errors.of_kind?(:password, :invalid)
  end

  test "keeps callbacks and configuration helpers private while preserving the public API" do
    internal_methods = %i[
      initialize_session_token_seed
      password_required?
      normalize_authentication_identity_attributes
      authentication_identity_attributes_are_present
      authentication_identity_attributes_are_unique
      authentication_email_is_valid
      authentication_identity_attributes
      normalize_authentication_attribute
      configured_email_attribute
      configured_user_name_attribute
      configured_email_confirmed_at_attribute
    ]
    public_methods = %i[
      email_verified?
      verify_email
      reset_session_token!
    ]

    internal_methods.each do |method|
      assert_includes User.private_instance_methods, method
      refute_includes User.public_instance_methods, method
    end
    public_methods.each do |method|
      assert_includes User.public_instance_methods, method
      refute_includes User.private_instance_methods, method
    end
  end
end
