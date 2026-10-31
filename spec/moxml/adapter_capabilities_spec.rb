# frozen_string_literal: true

# Processing model §Errors and loud degradation (normative): pinned here.

require "spec_helper"

# The engine capability report (#493): one structured face answering
# what the installed binding+engine serves — queried once at attach,
# the replacement for the version-gate-constant class. Only
# runtime-variable faces appear; anything the floor makes
# unconditional is absent by design. The two versions are never
# conflated: the binding vendors the engine, and the numbers differ.
RSpec.describe "engine capability report" do
  it "answers for leptris with both versions and known faces" do
    caps = Moxml::Adapter::Leptris.capabilities
    expect(caps).to be_frozen
    expect(caps[:binding_version]).to eq(Leptris::VERSION)
    expect(caps[:engine_version]).to match(/\A1\.\d+\.\d+/)
    expect(caps.keys).to include(
      :native_read_layer, :native_plan_structs, :native_plan_typed,
      :xsd, :relaxng, :xslt, :digest
    )
  end

  it "answers the ENGINE's version under engine_version, not the binding's" do
    caps = Moxml::Adapter::Leptris.capabilities
    engine = Leptris::XML::FFI.leptris_version
    expect(caps[:engine_version]).to eq(engine)
    if Gem::Version.new(Leptris::VERSION) != Gem::Version.new(engine)
      expect(caps[:binding_version]).not_to eq(caps[:engine_version]),
                                            "binding and engine versions are " \
                                            "different numbers; the report must " \
                                            "never conflate them"
    end
  end

  it "reports only booleans beyond the versions" do
    caps = Moxml::Adapter::Leptris.capabilities
    caps.except(:binding_version, :engine_version).each_value do |value|
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

  # leptris-ruby#572: the binding bridges the engine's capability
  # descriptor, and the support faces answer its verdict ANDed with
  # the binding probe — a face the engine serves but the binding has
  # not bridged is not "true" (the half-face trap the version-gate
  # class could not see).
  it "answers the support faces from the engine descriptor bitset" do
    skip "requires the binding's descriptor bridge (leptris 1.9.396+)" unless
      defined?(Leptris::XML.capabilities)

    caps = Moxml::Adapter::Leptris.capabilities
    descriptor = Leptris::XML.capabilities
    expect(descriptor[:descriptor_version]).to be(1)
    {
      digest: 1 << 9,
      xsd: 1 << 10,
      relaxng: 1 << 12,
      xslt: 1 << 14,
    }.each do |face, bit|
      served = descriptor[:caps].anybits?(bit)
      expect(caps[face]).to eql(served),
                            "#{face} must answer the engine bitset's verdict " \
                            "(ANDed with the binding probe)"
    end
  end

  it "is memoized — repeated queries answer the same frozen object" do
    expect(Moxml::Adapter::Leptris.capabilities)
      .to equal(Moxml::Adapter::Leptris.capabilities)
  end

  it "answers nil on adapters without a capability story" do
    expect(Moxml::Adapter::Base.capabilities).to be_nil
  end
end
