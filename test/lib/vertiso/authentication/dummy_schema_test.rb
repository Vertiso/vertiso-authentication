# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationDummySchemaTest < ActiveSupport::TestCase
  setup do
    configure_mapped_principal if User.attribute_names.include?("handle")
  end

  teardown do
    Vertiso::Authentication.reset_configuration!
  end

  test "persists a user in the selected dummy app schema" do
    user = User.create!(user_attributes)

    assert_predicate user, :persisted?
  end

  private

  # Returns required attributes for the selected dummy application's User.
  #
  # @return [Hash] attributes accepted by the selected User model
  def user_attributes
    attributes = {
      email: "user@example.com",
      password: "TestPassword1234!"
    }

    if User.attribute_names.include?("handle")
      attributes[:handle] = "example-user"
    else
      attributes[:user_name] = "example-user"
    end

    attributes
  end

  # Configures the mapped dummy's host principal attributes for this process.
  #
  # @return [void]
  def configure_mapped_principal
    Vertiso::Authentication.configure do |config|
      config.user_name_attribute = :handle
      config.email_confirmed_at_attribute = :email_confirmed_at
    end
  end
end
