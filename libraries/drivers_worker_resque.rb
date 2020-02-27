# frozen_string_literal: true

module Drivers
  module Worker
    class Resque < Drivers::Worker::Base
      adapter :resque
      allowed_engines :resque
      output filter: %i[process_count syslog workers queues]
      packages :monit, debian: 'redis-server', rhel: 'redis'

      def configure
        add_worker_monit

        add_scheduler_monit if configure_resque_web
      end

      def after_deploy
        restart_monit

        restart_scheduler_monit if configure_resque_web
      end
      alias after_undeploy after_deploy

      private

      def add_scheduler_monit
        opts = { application: app['shortname'], name: app['name'], out: out, deploy_to: deploy_dir(app),
                 environment: environment, adapter: adapter, app_shortname: app['shortname'] }

        context.template File.join(node['monit']['basedir'], "resque-scheduler_#{opts[:application]}.monitrc") do
          mode '0640'
          source "resque-scheduler.monitrc.erb"
          variables opts
        end

        context.execute 'monit reload'
      end

      def restart_scheduler_monit
        return if ENV['TEST_KITCHEN'] # Don't like it, but we can't run multiple processes in Docker on travis

        context.execute "monit restart resque_#{app['shortname']}-scheduler" do
          retries 3
        end
      end

      def configure_resque_web
        node['deploy'][app['shortname']].try(:[], 'worker').try(:[], 'enable_resque_scheduler')
      end
    end
  end
end
