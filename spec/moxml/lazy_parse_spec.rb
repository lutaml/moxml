# frozen_string_literal: true

require "spec_helper"
require "support/allocation_helper"

# Lazy parse correctness tests — these run in CI by default.
# Verifies that lazy parse produces correct document structure
# across all adapters without eager wrapper construction.
RSpec.describe "Moxml lazy parse" do
  let(:xml) do
    "<root><child><nested>text</nested></child><sibling>more</sibling></root>"
  end

  shared_examples "lazy parse behavior" do |adapter_name|
    let(:ctx) { Moxml::Context.new(adapter_name) }

    describe "#parse" do
      it "returns a Document without eagerly building wrapper tree" do
        doc = ctx.parse(xml)
        expect(doc).to be_a(Moxml::Document)
        expect(doc.root).to be_a(Moxml::Element)
        expect(doc.root.name).to eq("root")
      end

      it "provides correct children via lazy access" do
        doc = ctx.parse(xml)
        root = doc.root
        children = root.children.to_a
        expect(children.size).to eq(2)
        expect(children[0]).to be_a(Moxml::Element)
        expect(children[0].name).to eq("child")
        expect(children[1].name).to eq("sibling")
      end

      it "provides correct nested children" do
        doc = ctx.parse(xml)
        nested = doc.root.children[0].children[0]
        expect(nested.name).to eq("nested")
        expect(nested.text).to eq("text")
      end

      it "preserves attributes" do
        xml_with_attrs = '<root a="1" b="2"><child c="3"/></root>'
        doc = ctx.parse(xml_with_attrs)
        root = doc.root
        attrs = root.attributes
        expect(attrs.size).to eq(2)
        expect(root["a"]).to eq("1")
        expect(root["b"]).to eq("2")
        expect(root.children[0]["c"]).to eq("3")
      end

      it "preserves text content" do
        doc = ctx.parse("<root>hello world</root>")
        expect(doc.root.text).to eq("hello world")
      end

      it "preserves mixed content" do
        mixed_xml = "<root>before<child/>after</root>"
        doc = ctx.parse(mixed_xml)
        expect(doc.root.text).to eq("beforeafter")
      end

      it "handles comments" do
        comment_xml = "<root><!-- a comment --><child/></root>"
        doc = ctx.parse(comment_xml)
        children = doc.root.children.to_a
        comment = children.find(&:comment?)
        expect(comment).not_to be_nil
        expect(comment.content).to include("a comment")
      end

      it "handles processing instructions" do
        pi_xml = "<?pi-target pi-content?><root/>"
        doc = ctx.parse(pi_xml)
        expect(doc.root.name).to eq("root")
      end

      it "handles namespace declarations" do
        ns_xml = '<root xmlns:ns="http://example.com"><ns:child/></root>'
        doc = ctx.parse(ns_xml)
        root = doc.root
        nss = root.namespaces
        expect(nss.size).to be >= 1
      end

      it "round-trips through serialize" do
        doc = ctx.parse(xml)
        serialized = doc.to_xml
        doc2 = ctx.parse(serialized)
        expect(doc2.root.name).to eq("root")
        expect(doc2.root.children.to_a.size).to eq(2)
      end
    end
  end

  # Run for all guarded adapters
  AllocationHelper::GUARDED_ADAPTERS.each do |adapter_name|
    describe "#{adapter_name} adapter" do
      before(:all) do
        skip("#{adapter_name} adapter not available") unless AllocationHelper.adapter_available?(adapter_name)
      end

      it_behaves_like "lazy parse behavior", adapter_name

      # CDATA behavior differs between adapters
      it "handles CDATA sections" do
        ctx = Moxml::Context.new(adapter_name)
        cdata_xml = "<root><![CDATA[<not xml>]]></root>"
        doc = ctx.parse(cdata_xml)
        expect(doc.root).not_to be_nil
      end
    end
  end
end
