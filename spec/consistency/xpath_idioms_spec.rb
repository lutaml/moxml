# frozen_string_literal: true

# Processing model §Names and namespaces (normative): pinned here.
# Processing model §XPath evaluation (normative): pinned here.

require "spec_helper"

# Cross-adapter XPath idioms that nokogiri consumers rely on:
#
# - The literal xmlns: prefix resolves against the default namespace
#   (the libxml2 quirk that is nokogiri's documented way to match
#   default-namespaced elements; leptris carries it since engine
#   1.9.359 / leptris-ruby#469; moxml's own engine always has).
# - Attribute-terminal steps work in every path position
#   (leptris-ruby#458's table: //a/@id, //@id, r/a/@id,
#   //*[f()]/@id — fixed by the engine's VM path work).
CML_NS = "http://www.xml-cml.org/schema"
ACI_NS = "http://www.xml-cml.org/schema/asciichem"

RSpec.describe "XPath idioms across adapters" do
  let(:default_ns_xml) do
    '<svgmap xmlns="http://www.example.org/doc"><target href="a"/></svgmap>'
  end
  let(:plain_xml) { '<r><a id="x"><b/></a></r>' }
  let(:cml_xml) do
    <<~XML
      <molecule xmlns="#{CML_NS}" xmlns:aci="#{ACI_NS}" id="m1">
        <atomArray><atom id="a1"/></atomArray>
        <aci:group multiplicity="2" bracket="paren" atomRefs="a1"/>
      </molecule>
    XML
  end

  Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
    next if adapter_name == :headed_ox # same engine as :ox

    context "with #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      before do
        if adapter_name == :leptris &&
            Gem::Version.new(Leptris::VERSION) < Gem::Version.new("1.9.359.0")
          skip "binding #{Leptris::VERSION} predates the xmlns: fix (1.9.359)"
        end
      end

      it "matches default-namespaced elements via the xmlns: prefix" do
        doc = ctx.parse(default_ns_xml)
        targets = doc.root.xpath("./xmlns:target")
        expect(targets.length).to eq(1)
        expect(targets.first.name).to eq("target")
      end

      it "keeps explicit namespace bindings winning over the idiom" do
        doc = ctx.parse(default_ns_xml)
        targets = doc.root.xpath("./xmlns:target", "xmlns" => "urn:bogus")
        expect(targets).to be_empty
      end

      it "addresses the no-namespace default with an empty xmlns binding" do
        doc = ctx.parse(
          '<root xmlns="urn:a"><child xmlns="urn:b"><leaf xmlns=""/></child></root>',
        )
        leaf = doc.at_xpath("//xmlns:leaf", "xmlns" => "")
        expect(leaf&.name).to eq("leaf")
      end

      it "resolves attribute-terminal steps in every path position" do
        doc = ctx.parse(plain_xml)
        expect(doc.xpath("//a/@id").first&.value).to eq("x")
        expect(doc.xpath("//@id").first&.value).to eq("x")
        expect(doc.xpath("r/a/@id").first&.value).to eq("x")
        expect(doc.xpath("//*[local-name()='a']/@id").first&.value).to eq("x")
      end

      # Issue #395: bindings hashes arrive in both key spellings
      # (symbols are the common Nokogiri idiom); the engines must
      # resolve both — a symbol-key miss falls through to
      # prefix-spelling matching and namespaced elements never match.
      # asciichem's CML group extraction rides exactly this shape.
      it "resolves symbol-keyed namespace bindings" do
        doc = ctx.parse(cml_xml)
        mols = doc.xpath("//cml:molecule", cml: CML_NS)
        expect(mols.to_a.size).to eq(1)

        groups = mols.first.xpath("./aci:group", aci: ACI_NS)
        expect(groups.to_a.size).to eq(1)
        expect(groups.first["multiplicity"]).to eq("2")
      end

      it "resolves string-keyed namespace bindings identically" do
        doc = ctx.parse(cml_xml)
        expect(doc.xpath("//cml:molecule", "cml" => CML_NS).to_a.size).to eq(1)
      end

      # moxml#393: a relative name-test path on the DOCUMENT resolves
      # laxly, descendant-anchored at the root — Nokogiri's own
      # Document#at/#search semantics, now pinned for every adapter.
      # Axes, node types and "." keep strict document context.
      it "resolves document-context relative name-test paths from the root" do
        doc = ctx.parse(plain_xml)
        expect(doc.at("a/b")&.name).to eq("b")
        expect(doc.at_xpath("a/b")&.name).to eq("b")
        expect(doc.xpath("a/b").map(&:name)).to eq(["b"])
        expect(doc.xpath("a | r").map(&:name).sort).to eq(%w(a r))
        expect(doc.xpath("missing").map(&:name)).to eq([])
        expect(doc.at_xpath("missing")).to be_nil
      end

      it "keeps non-name-test expressions in document context" do
        doc = ctx.parse(plain_xml)
        expect(doc.at_xpath(".")).to be_truthy
        expect(doc.at_xpath("/*")&.name).to eq("r")
        expect(doc.at_xpath("/r")&.name).to eq("r")
      end

      it "answers scalar XPath functions unwrapped and uniform" do
        doc = ctx.parse(plain_xml)
        expect(doc.xpath("count(//a)")).to eq(1.0)
        expect(doc.xpath("string(//a/@id)")).to eq("x")
        expect(doc.xpath("boolean(//b)")).to be(true)
        expect(doc.at_xpath("count(//a)")).to eq(1.0)
      end

      # The live-tree contract: a sibling inserted after an XPath
      # evaluation must be visible to at_xpath and xpath. leptris's
      # node-set lane caches a document index that sibling insertions
      # do not rebuild (engine bug, tracked upstream); the adapter
      # routes such documents to the reference engine until a child
      # insertion rebuilds the index.
      it "answers at_xpath and xpath from the live tree after a sibling insertion" do
        doc = ctx.parse("<r><a><b/></a></r>")
        doc.xpath("//a")
        doc.at("//a").next = "<c/>"
        expect(doc.at("//c")&.name).to eq("c")
        expect(doc.xpath("//c").map(&:name)).to eq(["c"])
        expect(doc.at_xpath("count(//c)")).to eq(1.0)
      end
    end
  end
end
