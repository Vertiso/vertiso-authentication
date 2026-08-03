# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rake/testtask"

Rake::TestTask.new do |task|
  task.libs << "lib"
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

task default: :test
