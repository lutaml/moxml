# frozen_string_literal: true

require "spec_helper"

# The customized_* layer's doctrine (#495): each namespace module is
# either a tracked shim (an engine gap with a stated resolution) or an
# adapter-fate case (dies with its deprecated adapter). A Customized*
# file exists only when its header says which — the record is
# checkable, not folklore.
RSpec.describe "customized adapter layer lifecycle" do
  def customized_files
    Dir["lib/moxml/adapter/customized_*.rb"]
  end

  it "has customized namespaces to govern" do
    expect(customized_files).not_to be_empty
  end

  it "cites its lifecycle in every module header" do
    customized_files.each do |path|
      header = File.readlines(path).first(30).join
      expect(header).to match(/#\d{3}/),
                        "#{path} carries no lifecycle citation (#495)"
      expect(header).to match(/Lifecycle record|no native representation/),
                        "#{path} header does not state its lifecycle"
    end
  end

  it "marks adapter-fate cases as deprecated or Opal-bound" do
    adapter_fate = customized_files.reject { |p| p.include?("leptris") }
    expect(adapter_fate).not_to be_empty
    adapter_fate.each do |path|
      header = File.readlines(path).first(30).join
      expect(header).to match(/moxml#491|moxml#489/),
                        "#{path} is an adapter-fate case but cites neither " \
                        "its deprecation (#491) nor the Opal removal (#489)"
    end
  end

  it "keeps the tracked shim pointed at its resolution" do
    header = File.readlines("lib/moxml/adapter/customized_leptris.rb")
      .first(30).join
    expect(header).to include("tracked shim"), "the leptris shim must say so"
    expect(header).to include("dissolve into Base"),
                      "the leptris shim must state its end state"
  end
end
