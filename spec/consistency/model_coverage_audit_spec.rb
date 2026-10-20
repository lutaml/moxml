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
      section: "Document order and traversal",
      pin: "spec/consistency/adapter_parity_spec.rb",
    },
    "name resolution" => {
      section: "Names and namespaces",
      pin: "spec/consistency/xpath_idioms_spec.rb",
    },
    "namespace resolution and bindings normalization" => {
      section: "Names and namespaces",
      pin: "spec/consistency/xpath_idioms_spec.rb",
    },
    "attribute access" => {
      section: "Access semantics",
      pin: "spec/moxml/attribute_resolver_spec.rb",
    },
    "text/content/raw_content" => {
      section: "Access semantics",
      pin: "spec/moxml/text_spec.rb",
    },
    "parsing modes and diagnostics" => {
      section: "Parsing",
      pin: "spec/moxml/document_parse_diagnostics_spec.rb",
    },
    "EOL normalization" => {
      section: "Parsing",
      pin: "spec/consistency/eol_normalization_spec.rb",
      exempt: { oga: "D-02", ox: "D-03" },
    },
    "entity modes" => {
      section: "Parsing",
      pin: "spec/moxml/entity_spec.rb",
    },
    "XPath evaluation and declared idioms" => {
      section: "XPath evaluation",
      pin: "spec/consistency/xpath_idioms_spec.rb",
      exempt: { oga: "D-01" },
    },
    "serialization shapes (xml/html/xhtml)" => {
      section: "Serialization",
      pin: "spec/moxml/xhtml_output_spec.rb",
    },
    "indentation knobs" => {
      section: "Serialization",
      pin: "spec/moxml/to_html_spec.rb",
      exempt: { oga: "D-09", ox: "D-09", headed_ox: "D-09",
                libxml: "D-09", leptris: "D-09" },
    },
    "canonicalization" => {
      section: "Canonicalization",
      pin: "spec/moxml/c14n/adapter_delegation_spec.rb",
      exempt: { oga: "D-04", ox: "D-05", headed_ox: "D-05" },
    },
    "XSLT" => {
      section: "XSLT",
      pin: "spec/consistency/xslt_spec.rb",
      loud: { oga: "Moxml::NotImplementedError",
              ox: "Moxml::NotImplementedError",
              headed_ox: "Moxml::NotImplementedError",
              rexml: "Moxml::NotImplementedError",
              libxml: "Moxml::NotImplementedError" },
    },
    "SAX" => {
      section: "SAX",
      pin: "spec/moxml/sax_spec.rb",
    },
    "materialization" => {
      section: "Materialization",
      pin: "spec/moxml/plan_conformance_spec.rb",
    },
    "loud capability contracts" => {
      section: "Errors and loud degradation",
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

  # Model-derived governance: the matrix is generated FROM the model
  # doc's section headings, in both directions. A new section in
  # processing-model.adoc without a matrix citation (or an explicit
  # non-face declaration) fails this audit; a matrix citation whose
  # section vanished fails too.
  MODEL_DOC = "docs/_references/processing-model.adoc" # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  NON_FACE_SECTIONS = [ # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
    "Status and precedence",
    "Mission and invariant",
    "Object model",
    "Performance: a declared, non-semantic channel",
  ].freeze

  def model_sections
    File.readlines(MODEL_DOC).filter_map do |line|
      line[/\A=== (\S.*)$/, 1]&.strip
    end.uniq
  end

  it "cites an existing model section for every face family" do
    sections = model_sections
    unknown = MODEL_MATRIX.filter_map do |family, cell|
      section = cell[:section]
      next "#{family}: nil" if section.nil?

      "#{family}: #{section.inspect}" unless sections.include?(section)
    end
    expect(unknown).to be_empty,
                       "matrix families citing missing model sections: #{unknown.join('; ')}"
  end

  it "covers or declares every model section" do
    cited = MODEL_MATRIX.values.filter_map { |cell| cell[:section] }
    uncovered = model_sections.reject do |section|
      cited.include?(section) || NON_FACE_SECTIONS.include?(section)
    end
    expect(uncovered).to be_empty,
                         "model sections with no coverage matrix family " \
                         "(add a family or declare non-face): #{uncovered.join('; ')}"
  end

  it "declares non-face sections that actually exist in the model doc" do
    stale = NON_FACE_SECTIONS.reject { |s| model_sections.include?(s) }
    expect(stale).to be_empty,
                     "non-face declarations citing missing sections: #{stale.join('; ')}"
  end

  # Bidirectional linkage (TODO.sota/03): the model doc, the pins, and
  # the reference form one checkable triangle. Every pin cites the
  # section it enforces; every citation names a section that exists.
  PIN_CITATION = /Processing model §(.+?) \(normative\)/ # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  def pin_citations(path)
    File.readlines(path).filter_map { |line| line[PIN_CITATION, 1]&.strip }
  end

  it "has every pin cite the model section it enforces" do
    missing = MODEL_MATRIX.filter_map do |family, cell|
      next unless cell[:pin] && File.exist?(cell[:pin])

      "#{family}: #{cell[:pin]}" unless pin_citations(cell[:pin])
        .include?(cell[:section])
    end
    expect(missing).to be_empty,
                       "pins must cite their model section " \
                       "(# Processing model §<section>): #{missing.join('; ')}"
  end

  it "never cites a model section that does not exist" do
    sections = model_sections
    orphans = MODEL_MATRIX.filter_map { |_, cell| cell[:pin] }.uniq.flat_map do |path|
      next [] unless File.exist?(path)

      pin_citations(path).reject { |section| sections.include?(section) }
        .map { |section| "#{path}: #{section}" }
    end
    expect(orphans).to be_empty,
                       "pin citations naming missing sections: #{orphans.join('; ')}"
  end

  it "cites every face section from at least one pin" do
    cited = MODEL_MATRIX.filter_map { |_, cell| cell[:pin] }.uniq.flat_map do |path|
      File.exist?(path) ? pin_citations(path) : []
    end
    uncovered = model_sections.reject do |section|
      cited.include?(section) || NON_FACE_SECTIONS.include?(section)
    end
    expect(uncovered).to be_empty,
                         "model sections no pin cites: #{uncovered.join('; ')}"
  end
end
