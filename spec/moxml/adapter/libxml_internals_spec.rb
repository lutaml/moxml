# frozen_string_literal: true

begin
  require "libxml"
rescue LoadError
  return
end

require "moxml/adapter/libxml"

# Targeted tests for private helpers extracted during the perf refactor.
# The public `serialize` path covers them transitively, but a future
# refactor of those helpers benefits from fine-grained safety nets.
RSpec.describe Moxml::Adapter::Libxml do
  describe ".emit_children_with_layout" do
    let(:adapter) { described_class }

    def parse_root(xml)
      doc = LibXML::XML::Parser.string(xml).parse
      doc.root
    end

    def emit(root, indent_size: 2, depth: 0, eref_active: false)
      output = +""
      adapter.send(:emit_children_with_layout, output, root, indent_size, depth,
                   eref_active: eref_active)
      output
    end

    context "with all-element children" do
      it "emits a newline + per-level padding before each child" do
        root = parse_root("<root><a/><b/></root>")
        expect(emit(root)).to eq("\n  <a></a>\n  <b></b>")
      end

      it "emits no padding when indent_size is zero" do
        root = parse_root("<root><a/><b/></root>")
        expect(emit(root, indent_size: 0)).to eq("\n<a></a>\n<b></b>")
      end

      it "scales padding with depth" do
        root = parse_root("<root><a/></root>")
        expect(emit(root, depth: 2)).to eq("\n      <a></a>")
      end
    end

    context "with mixed text + element content" do
      it "does not emit newlines (text suppresses block layout)" do
        root = parse_root("<p>hello<b>world</b>!</p>")
        expect(emit(root)).to eq("hello<b>world</b>!")
      end

      it "emits a newline only before the first element when text follows" do
        root = parse_root("<p><b>world</b>!</p>")
        # First child is element, prev_block starts true → newline before it.
        # Then text "!" sets prev_block false; no further block-level
        # children follow, so no additional newlines.
        expect(emit(root)).to eq("\n  <b>world</b>!")
      end
    end

    context "with CDATA + element children" do
      it "treats cdata as text-like and suppresses surrounding newlines" do
        cdata_xml = "<r><![CDATA[X]]><a/></r>"
        root = parse_root(cdata_xml)
        # CDATA is text-like → no newline before it, prev_block goes false,
        # then <a/> follows but prev_block was set false by CDATA, so no \n.
        expect(emit(root)).to eq("<![CDATA[X]]><a></a>")
      end
    end

    context "with comment + element children" do
      it "treats comment as block-level and emits newlines between siblings" do
        root = parse_root("<x><!-- c --><y/></x>")
        expect(emit(root)).to eq("\n  <!-- c -->\n  <y></y>")
      end
    end

    context "with whitespace-only text children" do
      it "skips them and produces the same layout as a doc without them" do
        with_ws = emit(parse_root("<root>   <a/>   <b/>   </root>"))
        without_ws = emit(parse_root("<root><a/><b/></root>"))
        expect(with_ws).to eq(without_ws)
      end
    end

    context "with no children" do
      it "appends nothing" do
        root = parse_root("<empty/>")
        expect(emit(root)).to eq("")
      end
    end
  end

  describe ".lookup_entity_ref_serialization" do
    let(:adapter) { described_class }
    let(:context) { Moxml.new(:libxml) }

    # `lookup_entity_ref_serialization` is called from the recursive
    # serialize path with a raw libxml ::Node (not the wrapper), so we
    # unwrap to match the call-site contract.
    def libxml_native(moxml_node)
      adapter.send(:unpatch_node, moxml_node.native)
    end

    it "returns [nil, nil] when the document has no entity-ref attachments" do
      root = libxml_native(context.parse("<root><a/></root>").root)
      expect(adapter.send(:lookup_entity_ref_serialization, root)).to eq([nil, nil])
    end

    it "returns [nil, nil] for an element with no entity refs even when the doc has erefs elsewhere" do
      doc = context.parse("<root><a/><b/></root>")
      a = doc.root.children.first
      b = doc.root.children.last
      eref = Moxml::EntityReference.new(
        adapter.create_native_entity_reference("amp"), context
      )
      a.add_child(eref)

      expect(adapter.send(:lookup_entity_ref_serialization, libxml_native(b)))
        .to eq([nil, nil])
    end

    it "returns [refs, sequence] when both are registered for the element" do
      doc = context.parse("<root><a>text</a></root>")
      a = doc.root.children.first
      eref = Moxml::EntityReference.new(
        adapter.create_native_entity_reference("amp"), context
      )
      a.add_child(eref)

      refs, seq = adapter.send(:lookup_entity_ref_serialization, libxml_native(a))
      expect(refs).to be_an(Array).and(satisfy { |r| !r.empty? })
      expect(seq).to be_an(Array).and(include(:eref))
    end
  end
end
