# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  return
end

require "moxml/adapter/leptris"

# leptris-ruby#275 (binding 1.9.204, the remove half): attached
# DOCTYPEs materialize as native nodes with wrapper identity, and
# document-PI removal / declaration clear work natively. Below the
# gate the legacy CustomizedLeptris paths keep the contract.
RSpec.describe Moxml::Adapter::Leptris do
  around do |example|
    Moxml.with_config(:leptris, true, "UTF-8") do
      example.run
    end
  end

  let(:ctx) { Moxml.new(:leptris) }
  let(:gate) do
    Moxml::Adapter::Leptris::NATIVE_DOC_PARTS
  end

  describe "created DOCTYPE as a native node" do
    it "attaches, lists once with wrapper identity, serializes, and removes" do
      skip "requires binding 1.9.204+ (leptris-ruby#275)" unless gate

      doc = ctx.parse("<root/>")
      doctype = doc.create_doctype("root", "-//X//DTD Y//EN", "y.dtd")
      doc.add_child(doctype)

      listed = doc.children.grep(Moxml::Doctype)
      expect(listed.size).to eq(1)
      expect(listed.first).to equal(doctype)
      expect(doc.to_xml)
        .to include(%(<!DOCTYPE root PUBLIC "-//X//DTD Y//EN" "y.dtd">))

      doctype.remove
      expect(doc.children).to all(be_a(Moxml::Element))
      expect(doc.to_xml).not_to include("DOCTYPE")
    end
  end

  describe "document-level PI removal" do
    it "removes the PI from children and serialization" do
      skip "requires binding 1.9.204+ (leptris-ruby#275)" unless gate

      doc = ctx.parse("<root/>")
      doc.add_child(doc.create_processing_instruction("before", "data"))
      expect(doc.children.count { |c| c.is_a?(Moxml::ProcessingInstruction) })
        .to eq(1)

      doc.children
        .find { |c| c.is_a?(Moxml::ProcessingInstruction) }
        .remove
      expect(doc.children.count { |c| c.is_a?(Moxml::ProcessingInstruction) })
        .to eq(0)
      expect(doc.to_xml).not_to include("<?before")
    end
  end

  describe "declaration mirroring" do
    it "writes created declarations through to engine state and clears on remove" do
      skip "requires binding 1.9.204+ (leptris-ruby#275)" unless gate

      doc = ctx.parse("<root/>")
      declaration = doc.create_declaration("1.1", "UTF-8", "yes")
      doc.add_child(declaration)

      ffi = Leptris::XML::FFI
      native = doc.native
      expect(ffi.leptris_document_version(native.c_ptr)).to eq("1.1")
      expect(ffi.leptris_document_standalone(native.c_ptr)).to eq(1)
      expect(doc.to_xml).to include(%(version="1.1"))
      expect(doc.to_xml).to include(%(standalone="yes"))

      declaration.remove
      expect(doc.to_xml).not_to include("version=")
    end
  end
end
