# frozen_string_literal: true

module Drivers
  module Framework
    class Rails < Drivers::Framework::Base
      adapter :rails
      allowed_engines :rails
      output filter: %i[
        migrate migration_command deploy_environment assets_precompile assets_download_manifests
        manifests_s3_bucket assets_precompilation_command envs_in_console
      ]
      packages debian: %w[libxml2-dev tzdata zlib1g-dev], rhel: %w[libxml2-devel tzdata zlib-devel]
      log_paths lambda { |context|
        File.join(context.send(:deploy_dir, context.app), 'shared', 'log', '*.log')
      }

      def settings
        super.merge(deploy_environment: { 'RAILS_ENV' => deploy_env })
      end

      def configure
        rdses =
          context.search(:aws_opsworks_rds_db_instance).presence || [Drivers::Db::Factory.build(context, app)]
        rdses.each do |rds|
          database_yml(Drivers::Db::Factory.build(context, app, rds: rds))
        end
        super
      end

      def deploy_before_restart
        assets_download_manifests if out[:assets_download_manifests]
      end

      def deploy_after_restart
        setup_rails_console
      end

      private

      def assets_download_manifests
        git_revision = `git --git-dir #{context.release_path}/.git rev-parse --short=10 HEAD`.strip
        Chef::Log.info("Downloading manifests for git revision #{git_revision}")

        s3_helper = S3Helper.new(
          access_key: environment["S3_KEY"],
          secret_key: environment["S3_SECRET"],
          bucket:     out[:manifests_s3_bucket]["bucket_name"],
          region:     out[:manifests_s3_bucket]["aws_region"]
        )

        prefix = "manifests/#{git_revision}-"
        manifests = s3_helper.objects_by_prefix(prefix).contents

        if manifests.size < 2
          raise "Abort: missing one or more manifests for rev #{git_revision}"
        end

        manifests.each do |object|
          if object.key.include?("manifest.json")
            packs_path = File.join(context.release_path, "public", "packs")
            s3_helper.download(object.key, File.join(packs_path, "manifest.json"))
          elsif object.key.include?(".sprockets")
            sprockets_path = File.join(context.release_path, "public", "assets")
            file_name = object.key.gsub(/^manifests\/\w+-/, "")
            s3_helper.download(object.key, File.join(sprockets_path, file_name))
          end
        end
      end

      def database_yml(db_driver)
        return unless db_driver.applicable_for_configuration? && db_driver.can_migrate?

        database = db_driver.out
        deploy_environment = deploy_env

        context.template File.join(deploy_dir(app), 'shared', 'config', 'database.yml') do
          source 'database.yml.erb'
          mode '0660'
          owner node['deployer']['user'] || 'root'
          group www_group
          variables(database: database, environment: deploy_environment)
        end
      end

      def setup_rails_console
        return unless out[:envs_in_console]

        application_rb_path = File.join(deploy_dir(app), 'current', 'config', 'application.rb')

        return unless File.exist?(application_rb_path)

        # rubocop:disable Style/StringConcatenation
        env_code = "if(defined?(Rails::Console))\n  " +
                   environment.map { |key, value| "ENV['#{key}'] = #{value.inspect}" }.join("\n  ") +
                   "\nend\n"
        # rubocop:enable Style/StringConcatenation

        contents = File.read(application_rb_path).sub(/(^(?:module|class).*$)/, "#{env_code}\n\\1")

        File.open(application_rb_path, 'w') { |file| file.write(contents) }
      end

      def environment
        app['environment'].merge(out[:deploy_environment])
      end
    end
  end
end
