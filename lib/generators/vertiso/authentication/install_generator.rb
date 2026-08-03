# Copyright © 2026. Copyright Vertiso Corporation, all rights reserved.

require "rails/generators"
require "rails/generators/active_record"
require_relative "views_generator"

module Vertiso
  module Authentication
    module Generators
      # Installs the engine contract into an existing Rails application.
      class InstallGenerator < Rails::Generators::Base
        include Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        class_option :principal,
                     type: :string,
                     default: "User",
                     desc: "Host principal class"
        class_option :email_attribute,
                     type: :string,
                     default: "email",
                     desc: "Host principal email attribute"
        class_option :user_name_attribute,
                     type: :string,
                     default: "user_name",
                     desc: "Host principal unique handle attribute"
        class_option :email_confirmed_at_attribute,
                     type: :string,
                     default: "email_verified_at",
                     desc: "Host principal email-confirmation timestamp"
        class_option :mount_path,
                     type: :string,
                     default: "/authentication",
                     desc: "Engine route mount path"
        class_option :views,
                     type: :boolean,
                     default: false,
                     desc: "Copy components for host overrides"

        # Returns sequential migration numbers for one generator invocation.
        #
        # @param _dirname [String] migration destination
        # @return [String]
        def self.next_migration_number(_dirname)
          @migration_number =
            (@migration_number || Time.now.utc.strftime("%Y%m%d%H%M%S").to_i) + 1
          @migration_number.to_s
        end

        # Creates the host initializer with mapped field names.
        #
        # @return [void]
        def create_initializer
          template(
            "initializer.rb.tt",
            "config/initializers/vertiso_authentication.rb"
          )
        end

        # Adds the engine concern to the existing host principal.
        #
        # @return [void]
        def include_authenticatable
          path = principal_model_path
          unless File.exist?(destination_path(path))
            raise Thor::Error, "Principal model not found: #{path}"
          end
          return if File.read(destination_path(path)).include?(
            "include Vertiso::Authentication::Authenticatable"
          )

          inject_into_class(
            path,
            principal_class_name,
            "  include Vertiso::Authentication::Authenticatable\n"
          )
        end

        # Copies portable engine and principal migrations.
        #
        # @return [void]
        def copy_migrations
          migration_template(
            "create_authentication_sessions.rb.tt",
            "db/migrate/create_vertiso_authentication_authentication_sessions.rb"
          )
          migration_template(
            "create_oauth_providers.rb.tt",
            "db/migrate/create_vertiso_authentication_oauth_providers.rb"
          )
          migration_template(
            "create_user_oauth_accounts.rb.tt",
            "db/migrate/create_vertiso_authentication_user_oauth_accounts.rb"
          )
          migration_template(
            "add_authentication_to_principal.rb.tt",
            "db/migrate/add_authentication_to_#{principal_table_name}.rb"
          )
          migration_template(
            "add_principal_authentication_fields.rb.tt",
            "db/migrate/add_vertiso_authentication_fields_to_#{principal_table_name}.rb"
          )
        end

        # Mounts the isolated engine using the host's normal routes file.
        #
        # @return [void]
        def mount_engine
          statement =
            "mount Vertiso::Authentication::Engine => " \
            "\"#{options[:mount_path]}\""
          return if File.read(destination_path("config/routes.rb")).include?(
            statement
          )

          route statement
        end

        # Imports the Tailwind engine entrypoint exactly once.
        #
        # @return [void]
        def register_tailwind
          path = "app/assets/tailwind/application.css"
          import = '@import "../builds/tailwind/vertiso_authentication";'
          absolute_path = destination_path(path)
          unless File.exist?(absolute_path)
            create_file path, "@import \"tailwindcss\";\n"
          end
          return if File.read(absolute_path).include?(import)

          append_to_file path, "\n#{import}\n"
        end

        # Copies default components when explicitly requested.
        #
        # @return [void]
        def copy_views
          return unless options[:views]

          invoke Vertiso::Authentication::Generators::ViewsGenerator
        end

        private

        # @return [String]
        def principal_class_name
          options[:principal].to_s
        end

        # @return [String]
        def principal_model_path
          "app/models/#{principal_class_name.underscore}.rb"
        end

        # @return [String]
        def principal_table_name
          principal_class_name.tableize
        end

        # @return [String]
        def destination_path(path)
          File.join(destination_root, path)
        end
      end
    end
  end
end
