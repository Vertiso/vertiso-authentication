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

  spec.files = Dir["{app,config,lib,test}/**/*", "Gemfile", "Rakefile", "README.md"]
  spec.add_dependency "bcrypt"
  spec.add_dependency "omniauth"
  spec.add_dependency "omniauth-apple"
  spec.add_dependency "omniauth-github"
  spec.add_dependency "omniauth-google-oauth2"
  spec.add_dependency "omniauth-rails_csrf_protection"
  spec.add_dependency "rails", ">= 8.1"
  spec.add_dependency "tailwindcss-rails"
  spec.add_dependency "view_component", ">= 4.0"
  spec.add_development_dependency "sqlite3"
end
