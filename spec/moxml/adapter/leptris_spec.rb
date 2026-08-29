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
      doc = ctx.parse('<?xml version="1.0"?><?pi-prolog before?><root/><?pi-epilog after?><!-- tail -->')
      kids = doc.children.to_a

      expect(kids.map(&:class)).to eq(
        [Moxml::ProcessingInstruction, Moxml::Element,
         Moxml::ProcessingInstruction, Moxml::Comment],
      )
      expect(kids.select(&:processing_instruction?).map(&:target)).to eq(%w[pi-prolog pi-epilog])
      expect(kids[0].content).to eq("before")
      expect(doc.to_xml.index("pi-epilog")).to be > doc.to_xml.index("</root>")
      expect(doc.to_xml.index("<!-- tail -->")).to be > doc.to_xml.index("</root>")
    end

    it "round-trips tree-level PI mutations through serialization" do
      doc = ctx.parse("<root><a><?pi-original x?></a></root>")
      pi = doc.at_xpath("//a").children.to_a.find(&:processing_instruction?)
      pi.target = "renamed"
      pi.content = "changed"
      expect(doc.to_xml).to include("<?renamed changed?>")
    end

    it "adds document PIs and lists them as children" do
      doc = ctx.parse("<root/>")
      doc.add_child(doc.create_processing_instruction("added", "now"))
      expect(doc.to_xml).to include("<?added now?>")
      expect(doc.children.to_a.select(&:processing_instruction?).map(&:target)).to eq(%w[added])
    end

    it "keeps the document coherent across document-level PI mutation attempts" do
      # Divergent builds: libleptris 1.9.8 (released 1.9.32 platform
      # gems) accepts target= on parse-created document PIs; newer C
      # builds raise the descriptive contract error (leptris-ruby#92).
      # Pin the stable part — the document stays coherent either way.
      doc = ctx.parse("<?pi x?><root/>")
      pi = doc.children.to_a[0]

      begin
        pi.target = "renamed"
      rescue Leptris::XML::Error
        # rejected on this build
      end

      expect(doc.root.name).to eq("root")
      expect(doc.children.to_a.first.processing_instruction?).to be(true)
      expect(doc.to_xml).to match(/<root\s*\/?>|<root><\/root>/)
    end

    it "serializes children and document output in agreement" do
      # libleptris stores document PIs as one flat pre-root list (no
      # epilog anchoring); children and to_xml must at least agree.
      doc = ctx.parse('<?xml version="1.0"?><?pi-a 1?><root/><?pi-b 2?>')
      parts = doc.children.to_a.map { |c| "#{c.to_xml}\n" }.join
      from_document = doc.to_xml.sub(%r{\A<\?xml[^>]*\?>\n}, "")

      expect(from_document).to eq(parts)
    end

    it "matches raw Nokogiri byte-for-byte for pretty-printing (issue #129)" do
      source = %(<root><a/><b>x</b></root>)
      target = Nokogiri::XML(source).to_xml(indent: 2, encoding: "UTF-8")
      output = ctx.parse(source).to_xml(
        indent: 2, declaration: true, expand_empty: false, encoding: "UTF-8",
      )

      expect(output).to eq(target)
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

  describe "DTD ATTLIST defaults" do
    # libleptris 1.9.8: plain parse excludes ATTLIST defaults,
    # matching libxml2/Nokogiri/REXML; dtdattr: true opts in.
    let(:ctx) { Moxml.new(:leptris) }
    let(:dtd_xml) do
      %(<?xml version="1.0"?><!DOCTYPE doc [<!ATTLIST e9 attr CDATA "default">]><doc><e9/></doc>)
    end

    it "excludes ATTLIST defaults on plain parse" do
      skip "requires leptris with no-DTDATTR semantics" unless Moxml::Adapter::Leptris::DTDATTR_SUPPORTED

      doc = ctx.parse(dtd_xml)
      expect(doc.at_xpath("//e9")["attr"]).to be_nil
      expect(doc.to_xml).not_to include("attr=")
    end

    it "materializes ATTLIST defaults with dtdattr: true" do
      skip "requires leptris with ParseOptions::DTDATTR" unless Moxml::Adapter::Leptris::DTDATTR_SUPPORTED

      doc = ctx.parse(dtd_xml, dtdattr: true)
      expect(doc.at_xpath("//e9")["attr"]).to eq("default")
      expect(doc.to_xml).to include(%(attr="default"))
    end
  end

  describe "recover-path parse diagnostics" do
    let(:ctx) { Moxml.new(:leptris) }

    it "records the fatal error on non-strict parses" do
      doc = ctx.parse("<root><unclosed>", strict: false)
      expect(doc.root).to be_nil
      expect(doc.parse_errors).not_to be_empty
      expect(doc.parse_errors).to all(be_a(String))
    end

    it "answers [] on clean parses" do
      expect(ctx.parse("<root/>").parse_errors).to eq([])
    end

    it "still raises on strict parses" do
      expect { ctx.parse("<root><unclosed>") }.to raise_error(Moxml::ParseError)
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
