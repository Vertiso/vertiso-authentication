# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "test_helper"
require "rails/generators/test_case"

module VertisoAuthenticationGeneratorTestHelper
  private

  def build_host
    prepare_destination
    write_host_file(
      "app/models/member.rb",
      <<~RUBY
        class Member < ApplicationRecord
        end
      RUBY
    )
    write_host_file(
      "config/routes.rb",
      <<~RUBY
        Rails.application.routes.draw do
        end
      RUBY
    )
    write_host_file(
      "app/assets/tailwind/application.css",
      <<~CSS
        @import "tailwindcss";
      CSS
    )
  end

  def write_host_file(path, content)
    destination = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, content)
  end
end
