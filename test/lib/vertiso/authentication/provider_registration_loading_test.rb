# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "open3"

class VertisoAuthenticationProviderRegistrationLoadingTest < ActiveSupport::TestCase
  test "direct require loads every dependency needed by the public class" do
    script = <<~RUBY
      require "vertiso/authentication/provider_registration"

      registration = Vertiso::Authentication::ProviderRegistration.new(
        :google_oauth2,
        client_id: "client-id",
        client_secret: "client-secret"
      )
      abort "known provider not detected" unless registration.known?

      begin
        Vertiso::Authentication::ProviderRegistration.new(
          :google_oauth2,
          strategy: :google_oauth2
        )
      rescue Vertiso::Authentication::Omniauth::ProviderConfigurationError
        exit 0
      end

      abort "known strategy override was not rejected"
    RUBY
    stdout, stderr, status = Open3.capture3(
      Gem.ruby,
      "-I#{repository_root.join('lib')}",
      "-e",
      script
    )

    assert status.success?, "#{stdout}\n#{stderr}"
  end

  private

  # Returns the standalone gem repository root.
  #
  # @return [Pathname]
  def repository_root
    Pathname.new(File.expand_path("../../../..", __dir__))
  end
end
