# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"

class VertisoAuthenticationLoadTest < ActiveSupport::TestCase
  test "loads an isolated Rails engine" do
    assert_operator Vertiso::Authentication::Engine, :<, Rails::Engine
    assert_equal Vertiso::Authentication::Engine,
                 Vertiso::Authentication.railtie_namespace
  end
end
