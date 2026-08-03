# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "open3"

class TailwindProductionBuildTest < ActiveSupport::TestCase
  test "production build emits a utility used only by an engine component" do
    output_path = Rails.root.join("app/assets/builds/tailwind.css")
    FileUtils.rm_f(output_path)

    stdout, stderr, status = Open3.capture3(
      {
        "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__),
        "RAILS_ENV" => "production"
      },
      Gem.ruby,
      Gem.bin_path("rake", "rake"),
      "tailwindcss:build",
      chdir: Rails.root.to_s
    )

    assert status.success?, "#{stdout}\n#{stderr}"
    assert_path_exists output_path
    assert_includes File.read(output_path), ".min-h-dvh"
  ensure
    FileUtils.rm_f(output_path)
    FileUtils.rm_rf(Rails.root.join("app/assets/builds/tailwind"))
  end
end
