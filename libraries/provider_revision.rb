#
# Author:: Daniel DeLeo (<dan@kallistec.com>)
# Author:: Tim Hinderliter (<tim@chef.io>)
# Author:: Seth Falcon (<seth@chef.io>)
# Copyright:: Copyright 2009-2016, Daniel DeLeo
# Copyright:: Copyright 2010-2016, Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/provider'
require 'chef/json_compat'

class Chef
  class Provider
    class Deploy
      class Revision < Chef::Provider::Deploy
        provides :deploy_revision
        provides :deploy_branch

        def all_releases
          sorted_releases
        end

        def action_deploy
          validate_release_history!
          super
        end

        def cleanup!
          super

          known_releases = sorted_releases

          Dir["#{Chef::Util::PathHelper.escape_glob_dir(new_resource.deploy_to)}/releases/*"].each do |release_dir|
            next if known_releases.include?(release_dir)
            converge_by("Remove unknown release in #{release_dir}") do
              FileUtils.rm_rf(release_dir)
            end
          end
        end

        protected

        def release_created(release)
          sorted_releases { |r| r.delete(release); r << release }
        end

        def release_deleted(release)
          sorted_releases { |r| r.delete(release) }
        end

        def release_slug
          scm_provider.revision_slug
        end

        private

        def sorted_releases
          cache = load_cache
          if block_given?
            yield cache
            save_cache(cache)
          end
          cache
        end

        def validate_release_history!
          sorted_releases do |release_list|
            release_list.each do |path|
              release_list.delete(path) unless ::File.exist?(path)
            end
          end
        end

        def sorted_releases_from_filesystem
          Dir.glob(Chef::Util::PathHelper.escape_glob_dir(new_resource.deploy_to) + '/releases/*').sort_by { |d| ::File.ctime(d) }
        end

        def load_cache
          Chef::JSONCompat.parse(Chef::FileCache.load("revision-deploys/#{new_resource.name}"))
        rescue Chef::Exceptions::FileNotFound
          sorted_releases_from_filesystem
        end

        def save_cache(cache)
          Chef::FileCache.store("revision-deploys/#{new_resource.name}", Chef::JSONCompat.to_json(cache))
          cache
        end
      end
    end
  end
end
