# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationDummySchemaTest < ActiveSupport::TestCase
  test "persists a user in the selected dummy app schema" do
    user = User.create!(user_attributes)

    assert_predicate user, :persisted?
  end

  private

  # Returns required attributes for the selected dummy application's User.
  #
  # @return [Hash] attributes accepted by the selected User model
  def user_attributes
    attributes = { email: "user@example.com" }

    if User.attribute_names.include?("handle")
      attributes[:handle] = "example-user"
    else
      attributes[:name] = "Example User"
    end

    attributes
  end
end
