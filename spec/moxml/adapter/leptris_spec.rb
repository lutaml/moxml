# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end

# Programmatic document construction relies on the C API added for the
# Moxml integration (leptris_document_create / leptris_document_set_root,
# exposed as Leptris::XML::Document.create / #root=). Released leptris
# 1.1.x does not ship it yet; skip instead of failing until the binding
# release catches up.
unless Leptris::XML::Document.respond_to?(:create)
  # String form: the adapter constant is not loaded in this branch —
  # resolving it would raise NameError before the skip applies.
  RSpec.describe "Moxml::Adapter::Leptris" do
    it "waits for a leptris release with programmatic document construction" do
      skip "requires leptris with Leptris::XML::Document.create (unreleased C API)"
    end
  end

  return
end

require "moxml/adapter/leptris"

RSpec.describe Moxml::Adapter::Leptris do
  around do |example|
    Moxml.with_config(:leptris, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "native xpath dispatch" do
    let(:ctx) { Moxml.new(:leptris) }
    let(:doc) do
      ctx.parse(<<~XML)
        <root xmlns:p="http://x.org">
          <item id="1" p:kind="a">alpha</item>
          <item id="2">beta</item>
        </root>
      XML
    end

    it "evaluates document-context queries on the native engine" do
      expect(doc.xpath("//item[@id='2']").map(&:text)).to eq(["beta"])
      expect(doc.xpath("count(//item)")).to eq(2.0)
      expect(doc.xpath("//item[@p:kind='a']").map { |n| n["id"] }).to eq(["1"])
    end

    it "falls back to the Ruby engine for attribute-node results" do
      attrs = doc.xpath("//item/@id")
      expect(attrs.map(&:name)).to eq(%w[id id])
      expect(attrs.map(&:value)).to eq(%w[1 2])
    end

    it "evaluates element-context queries on the native engine" do
      expect(doc.root.xpath(".//item").size).to eq(2)
      first_item = doc.root.children.find(&:element?)
      expect(first_item.xpath("following-sibling::*").map(&:name)).to eq(%w[item])
    end

    it "falls back to the Ruby engine for parent-axis queries from the root" do
      # The binding reports the root element parentless; moxml roots
      # it at the document
      expect(doc.root.xpath("../*").size).to eq(1)
    end

    it "falls back to the Ruby engine for the xmlns: reserved prefix" do
      expect(doc.xpath("//xmlns:item").size).to eq(0)
      prefixed = ctx.parse('<r xmlns="http://d.org"><item/></r>')
      expect(prefixed.xpath("//xmlns:item").size).to eq(1)
    end

    it "raises Moxml::XPathError for invalid expressions" do
      expect { doc.xpath("//item[") }.to raise_error(Moxml::XPathError)
    end
  end

  describe "document-level processing instructions" do
    let(:ctx) { Moxml.new(:leptris) }

    it "lists document PIs as children with the root" do
      doc = ctx.parse('<?xml version="1.0"?><?pi-prolog before?><root/><?pi-epilog after?>')
      kids = doc.children.to_a

      expect(kids.map(&:class)).to eq(
        [Moxml::ProcessingInstruction, Moxml::ProcessingInstruction, Moxml::Element],
      )
      expect(kids.select(&:processing_instruction?).map(&:target)).to eq(%w[pi-prolog pi-epilog])
      expect(kids[0].content).to eq("before")
    end

    it "round-trips mutations and additions through serialization" do
      doc = ctx.parse("<?pi-original x?><root/>")
      pi = doc.children.to_a[0]
      pi.target = "renamed"
      pi.content = "changed"
      expect(doc.to_xml).to include("<?renamed changed?>")

      doc.add_child(doc.create_processing_instruction("added", "now"))
      expect(doc.to_xml).to include("<?added now?>")
      expect(doc.children.to_a.select(&:processing_instruction?).map(&:target)).to eq(%w[renamed added])
    end

    it "serializes children and document output in agreement" do
      # libleptris stores document PIs as one flat pre-root list (no
      # epilog anchoring); children and to_xml must at least agree.
      doc = ctx.parse('<?xml version="1.0"?><?pi-a 1?><root/><?pi-b 2?>')
      from_children = doc.children.to_a.select(&:processing_instruction?)
        .map(&:to_xml).join
      from_document = doc.to_xml.sub(%r{\A<\?xml[^>]*\?>}, "")

      expect(from_document).to start_with(from_children)
    end

    it "reports the tracked native for a re-added document PI" do
      doc = ctx.parse("<?pi-src orig?><root/>")
      moved = doc.children.to_a[0]
      target_doc = ctx.parse("<other/>")
      target_doc.add_child(moved)

      expect(target_doc.to_xml).to include("<?pi-src orig?>")
      expect(target_doc.children.to_a.select(&:processing_instruction?).map(&:target)).to include("pi-src")
    end
  end

  describe "entity-marker tracking" do
    let(:ctx) { Moxml.new(:leptris) }

    it "skips the marker split for entity-free documents" do
      doc = ctx.parse("<root>\n  <a>text</a>\n  <b/>\n</root>")
      kids = doc.root.children.to_a
      expect(kids.map(&:class)).to eq([Moxml::Text, Moxml::Element, Moxml::Text, Moxml::Element, Moxml::Text])
      expect(described_class.entity_bearing?(doc.root.native)).to be(false)
    end

    it "splits markers when the source carries entities" do
      doc = ctx.parse("<root><a>pre&nbsp;post</a></root>")
      kids = doc.at_xpath("//a").children.to_a
      expect(kids.map(&:class)).to include(Moxml::EntityReference)
      expect(described_class.entity_bearing?(doc.root.native)).to be(true)
    end

    it "returns serialized markup for entity-free documents" do
      # to_xml must not return nil when the restore scan is skipped
      doc = ctx.parse("<root><a>text</a></root>")
      expect(doc.to_xml).to include("<root>")
      expect(doc.at_xpath("//a").to_xml).to eq("<a>text</a>")
    end

    it "flips the flag when the builder mints an entity reference" do
      doc = ctx.parse("<root><a/></root>")
      expect(described_class.entity_bearing?(doc.root.native)).to be(false)

      er = doc.create_entity_reference("nbsp")
      doc.at_xpath("//a").add_child(er)
      expect(described_class.entity_bearing?(doc.root.native)).to be(true)
      expect(doc.at_xpath("//a").children.to_a.map(&:class)).to include(Moxml::EntityReference)
    end
  end
end
