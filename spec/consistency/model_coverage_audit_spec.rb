# frozen_string_literal: true

require "spec_helper"

# Model coverage matrix (TODO.model/03): every face family of the
# processing model is governed for every adapter — covered by a pin
# (the consistency/contract spec that asserts equivalence), exempt via
# a registered divergence (adapter => D-ID), or loud (adapter =>
# the named error class). An unpinned family is an ungoverned cell:
# this audit fails until it has one of the three.
# See docs/_references/processing-model.adoc for the model itself.
RSpec.describe "model coverage matrix" do
  MODEL_MATRIX = { # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
    "document order and children listing" => {
      pin: "spec/consistency/adapter_parity_spec.rb",
    },
    "name resolution" => {
      pin: "spec/consistency/xpath_idioms_spec.rb",
    },
    "namespace resolution and bindings normalization" => {
      pin: "spec/consistency/xpath_idioms_spec.rb",
    },
    "attribute access" => {
      pin: "spec/moxml/attribute_resolver_spec.rb",
    },
    "text/content/raw_content" => {
      pin: "spec/moxml/text_spec.rb",
    },
    "parsing modes and diagnostics" => {
      pin: "spec/moxml/document_parse_diagnostics_spec.rb",
    },
    "EOL normalization" => {
      pin: "spec/consistency/eol_normalization_spec.rb",
      exempt: { oga: "D-02", ox: "D-03" },
    },
    "entity modes" => {
      pin: "spec/moxml/entity_spec.rb",
    },
    "XPath evaluation and declared idioms" => {
      pin: "spec/consistency/xpath_idioms_spec.rb",
      exempt: { oga: "D-01" },
    },
    "serialization shapes (xml/html/xhtml)" => {
      pin: "spec/moxml/xhtml_output_spec.rb",
    },
    "indentation knobs" => {
      pin: "spec/moxml/to_html_spec.rb",
      exempt: { oga: "D-09", ox: "D-09", headed_ox: "D-09",
                libxml: "D-09", leptris: "D-09" },
    },
    "canonicalization" => {
      pin: "spec/moxml/c14n/adapter_delegation_spec.rb",
      exempt: { oga: "D-04", ox: "D-05", headed_ox: "D-05" },
    },
    "XSLT" => {
      pin: "spec/consistency/xslt_spec.rb",
      loud: { oga: "Moxml::NotImplementedError",
              ox: "Moxml::NotImplementedError",
              headed_ox: "Moxml::NotImplementedError",
              rexml: "Moxml::NotImplementedError",
              libxml: "Moxml::NotImplementedError" },
    },
    "SAX" => {
      pin: "spec/moxml/sax_spec.rb",
    },
    "materialization" => {
      pin: "spec/moxml/plan_conformance_spec.rb",
    },
    "loud capability contracts" => {
      pin: "spec/consistency/loud_degradation_spec.rb",
    },
  }.freeze

  def register_ids
    File.readlines("docs/_pages/divergences.adoc")
      .filter_map { |line| line[/\A\|\s*(D-\d+)\s*$/, 1] }
      .uniq
  end

  it "governs every face family with a pin" do
    unpinned = MODEL_MATRIX.reject { |_, cell| cell[:pin] }.keys
    expect(unpinned).to be_empty,
                        "ungoverned face families (no pin): " \
                        "#{unpinned.join(', ')}"
  end

  it "points every pin at an existing spec" do
    missing = MODEL_MATRIX.filter_map do |family, cell|
      family unless cell[:pin] && File.exist?(cell[:pin])
    end
    expect(missing).to be_empty, "pins missing on disk: #{missing.join(', ')}"
  end

  it "exempts adapters only via registered divergences" do
    unknown = MODEL_MATRIX.flat_map do |family, cell|
      (cell[:exempt] || {}).filter_map do |adapter, id|
        "#{family}: #{adapter} -> #{id}" unless register_ids.include?(id)
      end
    end
    expect(unknown).to be_empty,
                       "exemptions cite unregistered IDs: #{unknown.join('; ')}"
  end

  it "declares loud cells only with named Moxml errors" do
    bad = MODEL_MATRIX.flat_map do |family, cell|
      (cell[:loud] || {}).filter_map do |adapter, error|
        "#{family}: #{adapter} -> #{error}" unless error.start_with?("Moxml::")
      end
    end
    expect(bad).to be_empty,
                   "loud cells must name Moxml errors: #{bad.join('; ')}"
  end
end
