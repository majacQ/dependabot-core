# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::GoModules::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: github_credentials,
      ignored_versions: []
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "go_modules"
    )
  end
  let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }
  let(:dependency_version) { "1.0.0" }
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: dependency_version,
      groups: [],
      source: { type: "default", source: dependency_name }
    }]
  end
  let(:go_mod_content) do
    <<~GOMOD
      module foobar
      require #{dependency_name} v#{dependency_version}
    GOMOD
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: go_mod_content
      )
    ]
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    context "when a supported newer version is available" do
      it "updates to the newer version" do
        is_expected.to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end
    end

    context "doesn't update indirect dependencies (not supported)" do
      let(:requirements) { [] }
      it do
        is_expected.to eq(
          Dependabot::GoModules::Version.new(dependency.version)
        )
      end
    end

    it "updates v2+ modules"
    it "doesn't update to v2+ modules with un-versioned paths"
    it "updates modules that don't live at a repository root"
    it "updates Git SHAs to releases that include them"
    it "doesn't updates Git SHAs to releases that don't include them"
    it "doesn't update Git SHAs not on master to newer commits to master"
  end
end
