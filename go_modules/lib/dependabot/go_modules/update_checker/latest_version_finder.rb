# frozen_string_literal: true

require "excon"

require "dependabot/go_modules/update_checker"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/requirement"
require "dependabot/go_modules/resolvability_errors"

module Dependabot
  module GoModules
    class UpdateChecker
      class LatestVersionFinder
        RESOLVABILITY_ERROR_REGEXES = [
          # Package url/proxy doesn't include any redirect meta tags
          /no go-import meta tags/,
          # Package url 404s
          /404 Not Found/,
          /Repository not found/,
          /unrecognized import path/
        ].freeze
        PSEUDO_VERSION_REGEX = /\b\d{14}-[0-9a-f]{12}$/.freeze

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        private

        attr_reader :dependency, :dependency_files, :credentials, :ignored_versions

        def fetch_latest_version
          return dependency.version if dependency.version =~ PSEUDO_VERSION_REGEX

          candidate_versions = available_versions
          candidate_versions = filter_prerelease_versions(candidate_versions)
          candidate_versions = filter_ignored_versions(candidate_versions)

          candidate_versions.max
        end

        def available_versions
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              File.write("go.mod", go_mod.content)

              # Turn off the module proxy for now, as it's causing issues with
              # private git dependencies
              env = { "GOPRIVATE" => "*" }

              version_strings = SharedHelpers.run_helper_subprocess(
                command: NativeHelpers.helper_path,
                env: env,
                function: "getVersions",
                args: {
                  dependency: {
                    name: dependency.name,
                    version: "v" + dependency.version
                  }
                }
              )

              return [version_class.new(dependency.version)] if version_strings.nil?

              version_strings.select { |v| version_class.correct?(v) }.
                map { |v| version_class.new(v) }
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          retry if transitory_failure?(e) && retry_count < 2

          handle_subprocess_error(e)
        end

        def handle_subprocess_error(error)
          if RESOLVABILITY_ERROR_REGEXES.any? { |rgx| error.message =~ rgx }
            ResolvabilityErrors.handle(error.message, credentials: credentials)
          end

          raise
        end

        def transitory_failure?(error)
          return true if error.message.include?("EOF")

          error.message.include?("Internal Server Error")
        end

        def go_mod
          @go_mod ||= dependency_files.find { |f| f.name == "go.mod" }
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.version && version_class.correct?(dependency.version)

          versions_array.
            select { |version| version > version_class.new(dependency.version) }
        end

        def filter_ignored_versions(versions_array)
          filtered = versions_array.
                     reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          filtered
        end

        def wants_prerelease?
          @wants_prerelease ||=
            begin
              current_version = dependency.version
              current_version && version_class.correct?(current_version) &&
                version_class.new(current_version).prerelease?
            end
        end

        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end
      end
    end
  end
end
