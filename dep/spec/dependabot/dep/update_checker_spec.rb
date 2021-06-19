# frozen_string_literal: true

require "spec_helper"
require "dependabot/dep/update_checker"
require "dependabot/dep/metadata_finder"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Dep::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gopkg.toml",
        content: fixture("gopkg_tomls", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Gopkg.lock",
        content: fixture("gopkg_locks", lockfile_fixture_name)
      )
    ]
  end
  let(:manifest_fixture_name) { "no_version.toml" }
  let(:lockfile_fixture_name) { "no_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "dep"
    )
  end
  let(:requirements) do
    [{ file: "Gopkg.toml", requirement: req_str, groups: [], source: source }]
  end
  let(:dependency_name) { "github.com/dgrijalva/jwt-go" }
  let(:dependency_version) { "1.0.1" }
  let(:req_str) { nil }
  let(:source) { { type: "default", source: "github.com/dgrijalva/jwt-go" } }

  before do
    jwt_service_pack_url =
      "https://github.com/dgrijalva/jwt-go.git/info/refs"\
      "?service=git-upload-pack"
    stub_request(:get, jwt_service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", "jwt-go"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )

    mgo_service_pack_url =
      "https://github.com/globalsign/mgo.git/info/refs"\
      "?service=git-upload-pack"
    stub_request(:get, mgo_service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", "mgo"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )

    text_service_pack_url =
      "https://github.com/golang/text.git/info/refs"\
      "?service=git-upload-pack"
    stub_request(:get, text_service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", "text"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )

    color_service_pack_url =
      "https://github.com/fatih/color.git/info/refs"\
      "?service=git-upload-pack"
    stub_request(:get, color_service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", "color"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }
    it { is_expected.to eq(false) }

    context "with a git dependency" do
      let(:dependency_name) { "golang.org/x/text" }
      let(:source) do
        {
          type: "git",
          url: "https://github.com/golang/text",
          branch: branch,
          ref: ref
        }
      end

      before do
        repo_url = "https://api.github.com/repos/golang/text"
        stub_request(:get, repo_url + "/compare/v0.3.0...r2018.04.23").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_behind.json")
      end

      context "that specifies a tag as a version" do
        let(:manifest_fixture_name) { "tag_as_version.toml" }
        let(:lockfile_fixture_name) { "tag_as_version.lock" }
        let(:dependency_name) { "github.com/globalsign/mgo" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/globalsign/mgo",
            branch: nil,
            ref: "r2018.04.23"
          }
        end
        let(:req_str) { nil }
        let(:dependency_version) { "r2018.04.23" }

        it { is_expected.to eq(false) }
      end
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }
    it { is_expected.to eq(true) }

    context "with a git dependency" do
      let(:dependency_name) { "golang.org/x/text" }
      let(:source) do
        {
          type: "git",
          url: "https://github.com/golang/text",
          branch: branch,
          ref: ref
        }
      end

      before do
        repo_url = "https://api.github.com/repos/golang/text"
        stub_request(:get, repo_url + "/compare/v0.3.0...r2018.04.23").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_behind.json")
      end

      context "that specifies a tag as a version" do
        let(:manifest_fixture_name) { "tag_as_version.toml" }
        let(:lockfile_fixture_name) { "tag_as_version.lock" }
        let(:dependency_name) { "github.com/globalsign/mgo" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/globalsign/mgo",
            branch: nil,
            ref: "r2018.04.23"
          }
        end
        let(:req_str) { nil }
        let(:dependency_version) { "r2018.04.23" }

        it { is_expected.to eq(true) }
      end
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it "delegates to LatestVersionFinder" do
      expect(described_class::LatestVersionFinder).to receive(:new).with(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        ignored_versions: ignored_versions
      ).and_call_original

      expect(checker.latest_version).to eq(Gem::Version.new("3.2.0"))
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "delegates to VersionResolver" do
      prepped_files = described_class::FilePreparer.new(
        dependency_files: dependency_files,
        dependency: dependency,
        unlock_requirement: true,
        remove_git_source: false,
        latest_allowable_version: Gem::Version.new("3.2.0")
      ).prepared_dependency_files

      expect(described_class::VersionResolver).to receive(:new).with(
        dependency: dependency,
        dependency_files: prepped_files,
        credentials: credentials
      ).and_call_original

      expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.0"))
    end

    context "with an indirect dependency" do
      let(:requirements) { [] }
      it { is_expected.to eq(dependency.version) }
    end

    context "with a manifest file that needs unlocking" do
      let(:manifest_fixture_name) { "bare_version.toml" }
      let(:lockfile_fixture_name) { "bare_version.lock" }
      let(:req_str) { "1.0.0" }

      it "unlocks the manifest and gets the correct version" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.0"))
      end
    end

    context "with a git dependency" do
      let(:dependency_name) { "golang.org/x/text" }
      let(:source) do
        {
          type: "git",
          url: "https://github.com/golang/text",
          branch: branch,
          ref: ref
        }
      end

      before do
        repo_url = "https://api.github.com/repos/golang/text"
        stub_request(:get, repo_url + "/compare/v0.3.0...#{branch || ref}").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_behind.json")
      end

      context "that specifies a branch" do
        let(:manifest_fixture_name) { "branch.toml" }
        let(:lockfile_fixture_name) { "branch.lock" }
        let(:req_str) { nil }
        let(:dependency_version) { "7dd2c8130f5e924233f5543598300651c386d431" }
        let(:branch) { "master" }
        let(:ref) { nil }

        context "that is behind" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_behind.json")
          end

          it "updates to a released version" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("0.3.0"))
          end
        end
      end

      context "that specifies a tag" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }
        let(:req_str) { nil }
        let(:dependency_version) { "v0.2.0" }
        let(:branch) { nil }
        let(:ref) { "v0.2.0" }

        it "updates to a released version" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("0.3.0"))
        end

        context "as a version" do
          let(:manifest_fixture_name) { "tag_as_version.toml" }
          let(:lockfile_fixture_name) { "tag_as_version.lock" }
          let(:dependency_name) { "github.com/globalsign/mgo" }
          let(:source) do
            {
              type: "git",
              url: "https://github.com/globalsign/mgo",
              branch: nil,
              ref: "r2018.04.23"
            }
          end
          let(:req_str) { nil }
          let(:dependency_version) { "r2018.04.23" }

          it "returns the updated the tag name" do
            expect(latest_resolvable_version).to eq("r2018.06.15")
          end

          context "with the revision as the version" do
            let(:lockfile_fixture_name) { "tag_as_version_old.lock" }
            let(:dependency_version) do
              "efe0945164a7e582241f37ae8983c075f8f2e870"
            end

            it "returns the updated tag commit sha" do
              expect(latest_resolvable_version).
                to eq("113d3961e7311526535a1ef7042196563d442761")
            end
          end
        end
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }

    it "delegates to VersionResolver" do
      prepped_files = described_class::FilePreparer.new(
        dependency_files: dependency_files,
        dependency: dependency,
        unlock_requirement: true,
        remove_git_source: false,
        latest_allowable_version: Gem::Version.new("3.2.0")
      ).prepared_dependency_files

      expect(described_class::VersionResolver).to receive(:new).with(
        dependency: dependency,
        dependency_files: prepped_files,
        credentials: credentials
      ).and_call_original

      expect(checker.latest_resolvable_version_with_no_unlock).
        to eq(Gem::Version.new("3.2.0"))
    end

    context "with an indirect dependency" do
      let(:requirements) { [] }
      it { is_expected.to eq(dependency.version) }
    end

    context "with a manifest file that needs unlocking" do
      let(:manifest_fixture_name) { "bare_version.toml" }
      let(:lockfile_fixture_name) { "bare_version.lock" }
      let(:req_str) { "1.0.0" }

      it "doesn't unlock the manifest" do
        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("1.0.2"))
      end
    end

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/golang/text",
          branch: branch,
          ref: ref
        }
      end
      let(:dependency_name) { "golang.org/x/text" }

      before do
        repo_url = "https://api.github.com/repos/golang/text"
        stub_request(:get, repo_url + "/compare/v0.3.0...#{branch || ref}").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_behind.json")
      end

      context "that specifies a tag" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }
        let(:req_str) { nil }
        let(:dependency_version) { "v0.2.0" }
        let(:branch) { nil }
        let(:ref) { "v0.2.0" }

        it "doesn't unpin the commit" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq("v0.2.0")
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    it "delegates to RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).to receive(:new).with(
        requirements: dependency.requirements,
        updated_source: source,
        update_strategy: :widen_ranges,
        latest_version: "3.2.0",
        latest_resolvable_version: "3.2.0"
      ).and_call_original

      expect(checker.updated_requirements).to eq(
        [{
          file: "Gopkg.toml",
          requirement: nil,
          groups: [],
          source: { type: "default", source: "github.com/dgrijalva/jwt-go" }
        }]
      )
    end

    context "with a manifest file that needs unlocking" do
      let(:manifest_fixture_name) { "bare_version.toml" }
      let(:lockfile_fixture_name) { "bare_version.lock" }
      let(:req_str) { "1.0.0" }

      it "updates the requirements for the new version range" do
        expect(checker.updated_requirements).to eq(
          [{
            file: "Gopkg.toml",
            requirement: ">= 1.0.0, < 4.0.0",
            groups: [],
            source: { type: "default", source: "github.com/dgrijalva/jwt-go" }
          }]
        )
      end

      context "for an application" do
        before do
          dependency_files <<
            Dependabot::DependencyFile.new(
              name: "main.go",
              content: "code",
              type: "package_main"
            )
        end

        it "updates the requirements for the new version range" do
          expect(checker.updated_requirements).to eq(
            [{
              file: "Gopkg.toml",
              requirement: "3.2.0",
              groups: [],
              source: { type: "default", source: "github.com/dgrijalva/jwt-go" }
            }]
          )
        end
      end

      context "when a requirements_update_strategy has been specified" do
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            requirements_update_strategy: :bump_versions
          )
        end

        it "uses the specified requirements_update_strategy" do
          expect(described_class::RequirementsUpdater).to receive(:new).with(
            requirements: dependency.requirements,
            updated_source: source,
            update_strategy: :bump_versions,
            latest_version: "3.2.0",
            latest_resolvable_version: "3.2.0"
          ).and_call_original
          expect(checker.updated_requirements).to eq(
            [{
              file: "Gopkg.toml",
              requirement: "3.2.0",
              groups: [],
              source: { type: "default", source: "github.com/dgrijalva/jwt-go" }
            }]
          )
        end
      end
    end

    context "with a git dependency we should switch" do
      let(:manifest_fixture_name) { "tag_as_revision.toml" }
      let(:lockfile_fixture_name) { "tag_as_revision.lock" }

      let(:dependency_name) { "golang.org/x/text" }
      let(:req_str) { nil }
      let(:dependency_version) { "v0.2.0" }
      let(:source) do
        {
          type: "git",
          url: "https://github.com/golang/text",
          branch: nil,
          ref: "v0.2.0"
        }
      end

      before do
        repo_url = "https://api.github.com/repos/golang/text"
        stub_request(:get, repo_url + "/compare/v0.3.0...v0.2.0").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_behind.json")
      end

      it "updates the requirements for the new version range" do
        expect(checker.updated_requirements).to eq(
          [{
            file: "Gopkg.toml",
            requirement: "^0.3.0",
            groups: [],
            source: { type: "default", source: "golang.org/x/text" }
          }]
        )
      end
    end
  end
end
