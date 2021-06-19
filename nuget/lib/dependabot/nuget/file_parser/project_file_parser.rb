# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/nuget/file_parser"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class FileParser
      class ProjectFileParser
        require "dependabot/file_parsers/base/dependency_set"
        require_relative "property_value_finder"

        DEPENDENCY_SELECTOR = "ItemGroup > PackageReference, "\
                              "ItemGroup > GlobalPackageReference, "\
                              "ItemGroup > PackageVersion, "\
                              "ItemGroup > Dependency, "\
                              "ItemGroup > DevelopmentDependency"

        PROPERTY_REGEX      = /\$\((?<property>.*?)\)/.freeze
        ITEM_REGEX          = /\@\((?<property>.*?)\)/.freeze

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def dependency_set(project_file:)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          doc = Nokogiri::XML(project_file.content)
          doc.remove_namespaces!
          doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
            name = dependency_name(dependency_node, project_file)
            req = dependency_requirement(dependency_node, project_file)
            version = dependency_version(dependency_node, project_file)
            prop_name = req_property_name(dependency_node)

            dependency =
              build_dependency(name, req, version, prop_name, project_file)
            dependency_set << dependency if dependency
          end

          dependency_set
        end

        private

        attr_reader :dependency_files

        def build_dependency(name, req, version, prop_name, project_file)
          return unless name

          # Exclude any dependencies specified using interpolation
          return if [name, req, version].any? { |s| s&.include?("%(") }

          requirement = {
            requirement: req,
            file: project_file.name,
            groups: [],
            source: nil
          }

          if prop_name
            # Get the root property name unless no details could be found,
            # in which case use the top-level name to ease debugging
            root_prop_name = details_for_property(prop_name, project_file)&.
                             fetch(:root_property_name) || prop_name
            requirement[:metadata] = { property_name: root_prop_name }
          end

          Dependency.new(
            name: name,
            version: version,
            package_manager: "nuget",
            requirements: [requirement]
          )
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def dependency_name(dependency_node, project_file)
          raw_name =
            dependency_node.attribute("Include")&.value&.strip ||
            dependency_node.at_xpath("./Include")&.content&.strip ||
            dependency_node.attribute("Update")&.value&.strip ||
            dependency_node.at_xpath("./Update")&.content&.strip
          return unless raw_name

          # If the item contains @(ItemGroup) then ignore as it
          # updates a set of ItemGroup elements
          return if raw_name.match?(ITEM_REGEX)

          evaluated_value(raw_name, project_file)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def dependency_requirement(dependency_node, project_file)
          raw_requirement = get_node_version_value(dependency_node)
          return unless raw_requirement

          evaluated_value(raw_requirement, project_file)
        end

        def dependency_version(dependency_node, project_file)
          requirement = dependency_requirement(dependency_node, project_file)
          return unless requirement

          # Remove brackets if present
          version = requirement.gsub(/[\(\)\[\]]/, "").strip

          # We don't know the version for range requirements or wildcard
          # requirements, so return `nil` for these.
          return if version.include?(",") || version.include?("*") ||
                    version == ""

          version
        end

        def req_property_name(dependency_node)
          raw_requirement = get_node_version_value(dependency_node)
          return unless raw_requirement

          return unless raw_requirement.match?(PROPERTY_REGEX)

          raw_requirement.
            match(PROPERTY_REGEX).
            named_captures.fetch("property")
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def get_node_version_value(node)
          attribute = "Version"
          value =
            node.attribute(attribute)&.value&.strip ||
            node.at_xpath("./#{attribute}")&.content&.strip ||
            node.attribute(attribute.downcase)&.value&.strip ||
            node.at_xpath("./#{attribute.downcase}")&.content&.strip

          value == "" ? nil : value
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def evaluated_value(value, project_file)
          return value unless value.match?(PROPERTY_REGEX)

          property_name = value.match(PROPERTY_REGEX).
                          named_captures.fetch("property")
          property_details = details_for_property(property_name, project_file)

          # Don't halt parsing for a missing property value until we're
          # confident we're fetching property values correctly
          return value unless property_details&.fetch(:value)

          value.gsub(PROPERTY_REGEX, property_details&.fetch(:value))
        end

        def details_for_property(property_name, project_file)
          property_value_finder.
            property_details(
              property_name: property_name,
              callsite_file: project_file
            )
        end

        def property_value_finder
          @property_value_finder ||=
            PropertyValueFinder.new(dependency_files: dependency_files)
        end
      end
    end
  end
end
