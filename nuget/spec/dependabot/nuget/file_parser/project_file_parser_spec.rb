# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_parser/project_file_parser"

RSpec.describe Dependabot::Nuget::FileParser::ProjectFileParser do
  let(:file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
  end
  let(:file_body) { fixture("csproj", "basic.csproj") }
  let(:parser) { described_class.new(dependency_files: [file]) }

  describe "dependency_set" do
    subject(:dependency_set) { parser.dependency_set(project_file: file) }

    it { is_expected.to be_a(Dependabot::FileParsers::Base::DependencySet) }

    describe "the dependencies" do
      subject(:dependencies) { dependency_set.dependencies }

      its(:length) { is_expected.to eq(5) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Extensions.DependencyModel")
          expect(dependency.version).to eq("1.1.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.1",
              file: "my.csproj",
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies[1] }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.AspNetCore.App")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "my.csproj",
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("System.Collections.Specialized")
          expect(dependency.version).to eq("4.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "4.3.0",
              file: "my.csproj",
              groups: [],
              source: nil
            }]
          )
        end
      end

      context "with version ranges" do
        let(:file_body) { fixture("csproj", "ranges.csproj") }

        its(:length) { is_expected.to eq(4) }

        it "has the right details" do
          expect(dependencies.first.requirements.first.fetch(:requirement)).
            to eq("[1.0,2.0]")
          expect(dependencies.first.version).to be_nil

          expect(dependencies[1].requirements.first.fetch(:requirement)).
            to eq("[1.1]")
          expect(dependencies[1].version).to eq("1.1")

          expect(dependencies[2].requirements.first.fetch(:requirement)).
            to eq("(,1.0)")
          expect(dependencies[2].version).to be_nil

          expect(dependencies[3].requirements.first.fetch(:requirement)).
            to eq("1.0.*")
          expect(dependencies[3].version).to be_nil
        end
      end

      context "with an update specified" do
        let(:file_body) { fixture("csproj", "update.csproj") }

        it "has the right details" do
          expect(dependencies.map(&:name)).
            to match_array(
              %w(
                Microsoft.Extensions.DependencyModel
                Microsoft.AspNetCore.App
                Microsoft.Extensions.PlatformAbstractions
                System.Collections.Specialized
              )
            )
        end
      end

      context "with an updated package specified" do
        let(:file_body) { fixture("csproj", "packages.props") }

        it "has the right details" do
          expect(dependencies.map(&:name)).
            to match_array(
              %w(
                Microsoft.SourceLink.GitHub
                System.AskJeeves
                System.Google
                System.Lycos
                System.WebCrawler
              )
            )
        end
      end

      context "with an updated package specified" do
        let(:file_body) { fixture("csproj", "directory.packages.props") }

        it "has the right details" do
          expect(dependencies.map(&:name)).
            to match_array(
              %w(
                System.AskJeeves
                System.Google
                System.Lycos
                System.WebCrawler
              )
            )
        end
      end

      context "with a property version" do
        let(:file_body) do
          fixture("csproj", "property_version.csproj")
        end

        describe "the property dependency" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "Nuke.Common" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Nuke.Common")
            expect(dependency.version).to eq("0.1.434")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.434",
                file: "my.csproj",
                groups: [],
                source: nil,
                metadata: { property_name: "NukeVersion" }
              }]
            )
          end
        end

        context "that is indirect" do
          let(:file_body) do
            fixture("csproj", "property_version_indirect.csproj")
          end

          subject(:dependency) do
            dependencies.find { |d| d.name == "Nuke.Uncommon" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("Nuke.Uncommon")
            expect(dependency.version).to eq("0.1.434")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.434",
                file: "my.csproj",
                groups: [],
                source: nil,
                metadata: { property_name: "NukeVersion" }
              }]
            )
          end
        end

        context "that can't be found" do
          let(:file_body) do
            fixture("csproj", "missing_property_version.csproj")
          end

          describe "the property dependency" do
            subject(:dependency) do
              dependencies.find { |d| d.name == "Nuke.Common" }
            end

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("Nuke.Common")
              expect(dependency.version).to eq("$UnknownVersion")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "$(UnknownVersion)",
                  file: "my.csproj",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "UnknownVersion" }
                }]
              )
            end
          end
        end
      end

      context "with a nuproj" do
        let(:file_body) { fixture("csproj", "basic.nuproj") }

        it "has the right details" do
          expect(dependencies.map(&:name)).
            to match_array(%w(nanoFramework.CoreLibrary))
        end
      end

      context "with an interpolated value" do
        let(:file_body) { fixture("csproj", "interpolated.proj") }

        it "excludes the dependencies specified using interpolation" do
          expect(dependencies.count).to eq(0)
        end
      end
    end
  end
end
