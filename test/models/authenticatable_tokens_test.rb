# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require 'test_helper'

class VertisoAuthenticationAuthenticatableTokensTest < ActiveSupport::TestCase
  setup do
    configure_mapped_host if mapped_host?
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test 'remember token expires using the configured lifetime' do
    user = create_user
    token = user.generate_token_for(:remember_token)

    assert_equal user, User.find_by_token_for(:remember_token, token)

    travel 31.days

    assert_nil User.find_by_token_for(:remember_token, token)
  end

  test 'rotating the session seed invalidates issued remember tokens' do
    user = create_user
    token = user.generate_token_for(:remember_token)

    user.reset_session_token!

    assert_nil User.find_by_token_for(:remember_token, token)
  end

  test 'new principals receive a non-empty session token seed' do
    user = create_user

    assert_predicate user.session_token_seed, :present?
  end

  test 'email verification token expires after 24 hours' do
    user = create_user
    token = user.generate_token_for(:email_verification)

    assert_equal user, User.find_by_token_for(:email_verification, token)

    travel 25.hours

    assert_nil User.find_by_token_for(:email_verification, token)
  end

  test 'email changes invalidate issued email verification tokens' do
    user = create_user
    token = user.generate_token_for(:email_verification)

    user.update!(email: 'new-person@example.com')

    assert_nil User.find_by_token_for(:email_verification, token)
  end

  test 'verify email stores the timestamp in the configured host attribute' do
    user = create_user

    assert_not_predicate user, :email_verified?
    assert user.verify_email
    assert_predicate user, :email_verified?
    assert_not_nil user.public_send(configured_email_confirmed_at_attribute)
  end

  test 'password reset token expires after one hour' do
    user = create_user
    token = user.generate_token_for(:password_reset)

    assert_equal user, User.find_by_token_for(:password_reset, token)

    travel 61.minutes

    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test 'email changes invalidate issued password reset tokens' do
    user = create_user
    token = user.generate_token_for(:password_reset)

    user.update!(email: 'new-person@example.com')

    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test 'password changes invalidate issued password reset tokens' do
    user = create_user
    token = user.generate_token_for(:password_reset)

    user.update!(
      password: 'NewTestPassword1234!',
      password_confirmation: 'NewTestPassword1234!'
    )

    assert_nil User.find_by_token_for(:password_reset, token)
  end

  private

  # @return [User]
  def create_user
    password = 'TestPassword1234!'
    attributes = {
      email: 'person@example.com',
      password:,
      password_confirmation: password
    }
    attributes[configured_user_name_attribute] = 'person'

    User.create!(attributes)
  end

  # @return [void]
  def configure_mapped_host
    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end
  end

  # @return [Symbol]
  def configured_user_name_attribute
    Vertiso::Authentication.configuration.user_name_attribute
  end

  # @return [Symbol]
  def configured_email_confirmed_at_attribute
    Vertiso::Authentication.configuration.email_confirmed_at_attribute
  end

  # @return [Boolean]
  def mapped_host?
    User.attribute_names.include?('handle')
  end
end
