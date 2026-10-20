# frozen_string_literal: true

require "spec_helper"
require "support/input_taxonomy"
require "support/xml_generator"

# The executable reference (TODO.sota/03): a pure-Ruby reader,
# writer, and normalizer that answer the processing model with no
# engine involved. The differential suite tests adapters against it;
# these specs pin the reference itself.
RSpec.describe Moxml::Reference do
  describe "parsing" do
    it "reads the object model, declaration, and document parts" do
      doc = described_class.parse(
        '<?xml version="1.0" encoding="UTF-8"?><!--lead--><r a="1"><b>t</b></r>',
      )
      expect(doc.declaration[:version]).to eq("1.0")
      expect(doc.declaration[:encoding]).to eq("UTF-8")
      expect(described_class.element_names(doc)).to eq(%w[r b])
      expect(doc.root.attribute_pairs).to eq([["a", "1"]])
      expect(described_class.comments(doc)).to eq(["lead"])
    end

    it "answers bare local names for prefixed sources" do
      doc = described_class.parse('<r xmlns:p="urn:a"><p:c p:x="1"/></r>')
      expect(described_class.element_names(doc)).to eq(%w[r c])
      expect(described_class.child_element_names(doc)).to eq([["c"], []])
      expect(doc.root.children.first.attribute_pairs).to eq([["x", "1"]])
    end

    it "expands built-in and numeric references, never comments or PI data" do
      doc = described_class.parse(
        "<r>&amp;&#65;&#x42;<![CDATA[<raw>]]><!-- c --><?pi d?></r>",
      )
      expect(doc.root.text).to eq("&AB<raw>")
      expect(described_class.processing_instructions(doc)).to eq([["pi", "d"]])
    end

    it "preserves DTD-declared general entities lexically (uniform lane)" do
      doc = described_class.parse(
        '<!DOCTYPE r [<!ENTITY x "expanded">]><r>&x;</r>',
      )
      expect(doc.root.text).to eq("&x;")
    end

    it "normalizes literal line endings but not character references" do
      doc = described_class.parse("<r>a\r\nb\rc&#xD;d</r>")
      expect(doc.root.text).to eq("a\nb\nc\rd")
    end

    it "normalizes literal attribute whitespace" do
      doc = described_class.parse(%(<r a="x\ty\nz"/>))
      expect(doc.root.attribute_pairs).to eq([["a", "x y z"]])
    end

    it "drops the PI separator from PI data" do
      doc = described_class.parse("<r><?pi   data  ?></r>")
      expect(described_class.processing_instructions(doc))
        .to eq([["pi", "data  "]])
    end

    it "answers the empty string for PI with no data" do
      doc = described_class.parse("<r><?pi?></r>")
      expect(described_class.processing_instructions(doc)).to eq([["pi", ""]])
    end
  end

  describe "totality over the input taxonomy" do
    it "parses every well-formed taxonomy fixture" do
      InputTaxonomy.well_formed.each do |input|
        expect { described_class.parse(input.xml) }
          .not_to raise_error, "#{input.id} must parse in the reference"
      end
    end

    it "raises a named ParseError for every malformed taxonomy fixture" do
      InputTaxonomy.malformed.each do |input|
        expect { described_class.parse(input.xml) }
          .to raise_error(Moxml::ParseError),
              "#{input.id} must raise in the reference"
      end
    end

    it "parses every generated document" do
      (1..10).each do |seed|
        expect { described_class.parse(XmlGenerator.generate(seed)) }
          .not_to raise_error
      end
    end
  end

  describe "writers" do
    let(:doc) do
      described_class.parse(
        '<r a="&lt;&amp;&quot;"><b/>t<!--c--><![CDATA[x<y]]></r>',
      )
    end

    it "emits XML that re-parses to the same information set" do
      xml = described_class.to_xml(doc)
      again = described_class.parse(xml)
      expect(described_class.element_names(again))
        .to eq(described_class.element_names(doc))
      expect(again.root.attribute_pairs).to eq(doc.root.attribute_pairs)
      expect(again.root.text).to eq(doc.root.text)
    end

    it "emits the canonical facade escaping" do
      expect(described_class.to_xml(doc))
        .to include('<r a="&lt;&amp;&quot;">')
      expect(described_class.to_xml(doc)).to include("<![CDATA[x<y]]>")
      expect(described_class.to_xml(doc)).to include("<b/>")
    end

    it "splits a CDATA end sequence" do
      document = Moxml::Reference::Document.new
      root = Moxml::Reference::Node.new(kind: :element, name: "r")
      root.children << Moxml::Reference::Node.new(kind: :cdata, data: "a]]>b")
      document.children << root
      expect(described_class.to_xml(document)).to include("]]]]><![CDATA[>")
    end

    it "leaves void elements unclosed in HTML and self-closed in XHTML" do
      html_doc = described_class.parse("<html><body>a<br/>b</body></html>")
      expect(described_class.to_html(html_doc)).to include("<br>")
      expect(described_class.to_xhtml(html_doc)).to include("<br/>")
    end

    it "emits raw text inside HTML script and style, escaped in XHTML" do
      html_doc = described_class.parse("<html><script>a &lt; b</script></html>")
      expect(described_class.to_html(html_doc))
        .to include("<script>a < b</script>")
      expect(described_class.to_xhtml(html_doc))
        .to include("<script>a &lt; b</script>")
    end

    it "emits no XML declaration unless the source had one" do
      expect(described_class.to_html(described_class.parse("<r/>")))
        .to eq("<r></r>")
      with_declaration = described_class.parse('<?xml version="1.0"?><r/>')
      expect(described_class.to_xml(with_declaration))
        .to start_with('<?xml version="1.0"?>')
    end
  end

  describe "normalizer" do
    it "normalizes CRLF and bare CR to LF" do
      expect(Moxml::Reference::Normalizer.normalize_eol("a\r\nb\rc"))
        .to eq("a\nb\nc")
    end

    it "expands built-ins and numeric references" do
      expect(Moxml::Reference::Normalizer.expand_entities("&lt;&#65;"))
        .to eq("<A")
    end

    it "raises for an undefined reference" do
      expect { Moxml::Reference::Normalizer.expand_entities("&nope;") }
        .to raise_error(Moxml::ParseError)
    end
  end
end
