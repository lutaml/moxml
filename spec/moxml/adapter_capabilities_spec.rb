# frozen_string_literal: true

# Processing model §Errors and loud degradation (normative): pinned here.

require "spec_helper"

# The engine capability report (#493): one structured face answering
# what the installed binding+engine serves — queried once at attach,
# the replacement for the version-gate-constant class. Only
# runtime-variable faces appear; anything the floor makes
# unconditional is absent by design.
RSpec.describe "engine capability report" do
  it "answers for leptris with the engine version and known faces" do
    caps = Moxml::Adapter::Leptris.capabilities
    expect(caps).to be_frozen
    expect(caps[:engine_version]).to match(/\A1\.\d+\.\d+/)
    expect(caps.keys).to include(
      :native_read_layer, :native_plan_structs, :native_plan_typed,
      :xsd, :relaxng, :xslt, :digest
    )
  end

  it "reports only booleans beyond the version" do
    caps = Moxml::Adapter::Leptris.capabilities
    caps.except(:engine_version).each_value do |value|
      expect(value).to eql(true).or eql(false)
    end
  end

  it "keeps the unwound internal gates out of the report" do
    caps = Moxml::Adapter::Leptris.capabilities
    expect(caps.keys).not_to include(
      :prefixed_attr_predicates_native, :libxml2_layout_parity,
      :indent_unit_supported, :element_unit_comments,
      :native_bulk_sax_records, :native_document_parts, :native_plan_rows
    )
    expect(caps[:xsd]).to be(true)
    expect(caps[:xslt]).to be(true)
  end

  it "is memoized — repeated queries answer the same frozen object" do
    expect(Moxml::Adapter::Leptris.capabilities)
      .to equal(Moxml::Adapter::Leptris.capabilities)
  end

  it "answers nil on adapters without a capability story" do
    expect(Moxml::Adapter::Base.capabilities).to be_nil
  end
end
