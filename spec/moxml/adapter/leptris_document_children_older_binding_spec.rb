# frozen_string_literal: true

require "spec_helper"

# The document-children listing filters the declaration node, but on
# leptris releases that predate the Declaration class entirely
# (< 1.9.360) referencing the constant raised NameError on every
# document-children enumeration — the first `doc.children` on any
# document. The filter must resolve the constant conditionally.
RSpec.describe "leptris document children on older leptris" do
  let(:ctx) { Moxml.new(:leptris) }

  it "lists document children when the release has no Declaration class" do
    leptris_xml = Leptris::XML
    had_declaration = leptris_xml.const_defined?(:Declaration, false)
    declaration = had_declaration ? leptris_xml.const_get(:Declaration) : nil
    # stub_const cannot express a MISSING constant; simulating the
    # older binding requires the constant to be absent
    if had_declaration
      leptris_xml.send(:remove_const, :Declaration) # rubocop:disable RSpec/RemoveConst
    end

    begin
      doc = ctx.create_document
      doc.add_child(doc.create_element("root"))
      expect(doc.children.map(&:name)).to eq(%w[root])
    ensure
      leptris_xml.const_set(:Declaration, declaration) if had_declaration
    end
  end

  it "keeps filtering the declaration on releases that have the class" do
    skip "binding #{Leptris::VERSION} has no Declaration class (D-21)" unless
      Leptris::XML.const_defined?(:Declaration, false)

    doc = ctx.parse(%(<?xml version="1.0" encoding="UTF-8"?>\n<documents></documents>))
    expect(doc.children.map(&:node_type)).to eq(%i[element])
  end
end
