# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

if ENV["VAUTH_TEST_CONFIGURE_OAUTH"] == "1"
  Vertiso::Authentication.configure do |configuration|
    configuration.oauth_provider(:custom, strategy: :custom)
  end
end
