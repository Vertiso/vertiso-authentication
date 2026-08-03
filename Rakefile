# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rake/testtask"
require "fileutils"

GEMSPEC_PATH = "vertiso-authentication.gemspec".freeze
PACKAGE_DIRECTORY = "pkg".freeze

Rake::TestTask.new do |task|
  task.libs << "lib"
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

namespace :test do
  desc "Run the full Minitest suite against SQLite"
  task :sqlite do
    sh(
      { "DATABASE_URL" => "sqlite3::memory:" },
      "bundle",
      "exec",
      "rake",
      "test"
    )
  end

  desc "Run the full Minitest suite against PostgreSQL from DATABASE_URL"
  task :postgresql do
    database_url = ENV.fetch("DATABASE_URL", "")
    abort "DATABASE_URL must identify a PostgreSQL test database" unless
      database_url.match?(%r{\Apostgres(?:ql)?://})

    sh "bundle", "exec", "rake", "test"
  end
end

namespace :quality do
  desc "Run RuboCop"
  task :rubocop do
    sh "bundle", "exec", "rubocop"
  end

  desc "Run Brakeman"
  task :brakeman do
    sh "bundle", "exec", "brakeman", "--no-pager"
  end

  desc "Run bundler-audit"
  task :audit do
    sh "bundle", "exec", "bundler-audit", "check", "--update"
  end
end

namespace :package do
  desc "Build the gem into pkg"
  task :build do
    specification = Gem::Specification.load(GEMSPEC_PATH)
    FileUtils.mkdir_p(PACKAGE_DIRECTORY)
    package_path = File.join(
      PACKAGE_DIRECTORY,
      "#{specification.full_name}.gem"
    )
    sh "gem", "build", GEMSPEC_PATH, "--output", package_path
  end

  desc "Build and validate the exact packaged contents"
  task validate: :build do
    specification = Gem::Specification.load(GEMSPEC_PATH)
    package_path = File.expand_path(
      File.join(PACKAGE_DIRECTORY, "#{specification.full_name}.gem")
    )
    sh(
      { "PACKAGE_PATH" => package_path },
      "bundle",
      "exec",
      "ruby",
      "-Itest",
      "test/lib/vertiso/authentication/package_test.rb"
    )
  end
end

desc "Run every adapter, quality, and package gate"
task ci: %w[
  test:sqlite
  test:postgresql
  quality:rubocop
  quality:brakeman
  quality:audit
  package:validate
]

task default: :test
