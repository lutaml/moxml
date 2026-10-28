# frozen_string_literal: true

require "spec_helper"

# Processing model §Validation (normative): pinned here.
# moxml#460 items 1-2: the engine's metadata routes through the
# facade. On bindings predating the faces the probes answer nil and
# the facade degrades exactly as before (rules heuristic / flat
# errors) — the degradation is part of the contract.
RSpec.describe "Moxml::XSD engine metadata" do
  let(:context) { Moxml.new(:leptris) }

  describe "degradation on faces-less adapters" do
    it "answers the source-derived version and nil structured rows" do
      ctx = Moxml.new(:nokogiri)
      skip "nokogiri requires an XSD-capable engine" unless
        Moxml::XSD.supported?(ctx)
      schema = ctx.xsd(
        "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" version=\"1.1\"><xs:element name=\"e\" type=\"xs:string\"/></xs:schema>",
      )
      expect(schema.version).to eq("1.0")
      expect(schema.structured_errors("<e/>")).to be_nil
    end
  end

  describe "Schema#version" do
    it "answers 1.1 for a 1.1-tagged schema when the binding serves it" do
      schema = context.xsd(
        '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" ' \
        'version="1.1">' \
        '<xs:element name="e" type="xs:string"/></xs:schema>',
      )
      v = schema.version
      expect(v).to eq("1.1").or eq("1.0")
    end

    it "answers 1.0 for an untagged schema" do
      schema = context.xsd(
        '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' \
        '<xs:element name="e" type="xs:string"/></xs:schema>',
      )
      expect(schema.version).to eq("1.0")
    end
  end

  describe "Schema#structured_errors" do
    it "returns rows with kind/component when the binding serves it" do
      schema = context.xsd(
        '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">' \
        '<xs:element name="note">' \
        "<xs:complexType><xs:sequence>" \
        '<xs:element name="to" type="xs:string"/>' \
        "</xs:sequence></xs:complexType>" \
        "</xs:element></xs:schema>",
      )
      # a WRONG child, not an empty instance: pre-1.9.383 engines
      # false-validate empty instances (leptris#1859) — this keeps
      # the spec meaningful across both engine generations
      rows = schema.structured_errors("<note><from>x</from></note>")
      skip "binding predates the structured report" if rows.nil?
      expect(rows).not_to be_empty
      expect(rows.first).to respond_to(:kind)
      expect(rows.first).to respond_to(:component)
    end
  end
end
