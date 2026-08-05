# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

Gem::Specification.new do |spec|
  spec.name = "vertiso-authentication"
  spec.version = "0.1.0"
  spec.authors = ["Vertiso Corporation"]
  spec.email = ["engineering@vertiso.com"]

  spec.summary = "Reusable authentication Rails engine for Vertiso applications."
  spec.description = "A reusable, isolated Rails engine for Vertiso authentication flows."
  spec.homepage = "https://vertiso.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/Vertiso/vertiso-authentication/issues",
    "changelog_uri" => "https://github.com/Vertiso/vertiso-authentication/blob/main/CHANGELOG.md",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/Vertiso/vertiso-authentication"
  }

  spec.files = Dir[
    "{app,config,db/migrate,lib}/**/*",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "SECURITY.md"
  ].select { |path| File.file?(path) }
  spec.add_dependency "bcrypt"
  spec.add_dependency "oauth2", ">= 2.0.22"
  spec.add_dependency "omniauth"
  spec.add_dependency "omniauth-rails_csrf_protection"
  spec.add_dependency "rails", ">= 8.1"
  spec.add_dependency "tailwindcss-rails"
  spec.add_dependency "view_component", ">= 4.0"
  spec.add_development_dependency "brakeman"
  spec.add_development_dependency "bundler-audit"
  spec.add_development_dependency "omniauth-apple"
  spec.add_development_dependency "omniauth-github"
  spec.add_development_dependency "omniauth-google-oauth2"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "sqlite3"
end
