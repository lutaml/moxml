# frozen_string_literal: true

require "spec_helper"

# Exercises feature areas under Opal that are not covered by the shared
# adapter contract (opal_oga_adapter_spec.rb) or the basic smoke spec
# (opal_oga_smoke_spec.rb). Targets the default Opal adapter (:oga).
# Uses an explicit :oga context so leaked global config from other specs
# cannot flip the adapter under test.
RSpec.describe "Moxml Opal oga feature coverage", if: RUBY_ENGINE == "opal" do
  let(:context) { Moxml.new(:oga) }

  describe "builder DSL" do
    it "builds a document with the block DSL" do
      doc = Moxml::Builder.new(context).build do
        root do
          child "text"
        end
      end

      expect(doc.root.name).to eq("root")
      expect(doc.root.children.first.name).to eq("child")
      expect(doc.root.children.first.text).to eq("text")
    end

    it "creates nested elements via blocks" do
      doc = Moxml::Builder.new(context).build do
        library do
          book(id: "1") { title "A" }
          book(id: "2") { title "B" }
        end
      end

      books = doc.root.children.select { |c| c.is_a?(Moxml::Element) }
      expect(books.length).to eq(2)
      expect(books.map { |b| b["id"] }).to eq(%w[1 2])
    end

    it "supports method_missing DSL with attributes and text" do
      doc = Moxml::Builder.new(context).build do
        person(name: "Alice", age: "30") { email "alice@example.com" }
      end

      person = doc.root
      expect(person.name).to eq("person")
      expect(person["name"]).to eq("Alice")
      expect(person["age"]).to eq("30")
      expect(person.children.first.name).to eq("email")
      expect(person.children.first.text).to eq("alice@example.com")
    end

    it "strips trailing underscore for reserved-name tags" do
      doc = Moxml::Builder.new(context).build do
        class_ { name "Foo" }
      end

      expect(doc.root.name).to eq("class")
    end

    it "attaches namespace declarations" do
      builder = Moxml::Builder.new(context)
      doc = builder.build do
        root("xmlns:dc": "http://purl.org/dc/elements/1.1/") do
          builder.element("dc:title") { builder.text "Hello" }
        end
      end

      title = doc.root.children.find { |c| c.is_a?(Moxml::Element) }
      expect(title.name).to eq("dc:title")
      expect(doc.to_xml).to include("xmlns:dc")
      expect(doc.to_xml).to include("dc:title")
    end
  end

  describe "XML declaration preservation" do
    it "does not add a declaration when the input has none" do
      doc = context.parse("<root><child/></root>")
      output = doc.to_xml

      expect(output).not_to include("<?xml")
      expect(doc.has_xml_declaration).to be false
    end

    it "preserves the declaration when the input has one" do
      xml = '<?xml version="1.0" encoding="UTF-8"?><root/>'
      doc = context.parse(xml)

      expect(doc.has_xml_declaration).to be true
      expect(doc.to_xml).to include("<?xml")
      expect(doc.to_xml).to include('version="1.0"')
    end

    it "forces the declaration on with declaration: true" do
      doc = context.parse("<root/>")
      expect(doc.to_xml(declaration: true)).to include("<?xml")
    end

    it "forces the declaration off with declaration: false" do
      doc = context.parse('<?xml version="1.0"?><root/>')
      expect(doc.to_xml(declaration: false)).not_to include("<?xml")
    end

    it "preserves standalone attribute" do
      xml = '<?xml version="1.0" standalone="yes"?><root/>'
      doc = context.parse(xml)
      expect(doc.to_xml).to include("standalone")
    end
  end

  describe "doctype handling" do
    it "parses a SIMPLE doctype" do
      doc = context.parse("<!DOCTYPE root><root/>")
      doctype = doc.children.find { |c| c.is_a?(Moxml::Doctype) }
      expect(doctype).not_to be_nil
      expect(doctype.name).to eq("root")
    end

    it "parses a PUBLIC doctype with external and system ids" do
      xml = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"><html/>'
      doc = context.parse(xml)
      doctype = doc.children.find { |c| c.is_a?(Moxml::Doctype) }

      expect(doctype).not_to be_nil
      expect(doctype.name).to eq("html")
      expect(doctype.external_id).to eq("-//W3C//DTD HTML 4.01//EN")
      expect(doctype.system_id).to eq("http://www.w3.org/TR/html4/strict.dtd")
    end

    it "round-trips the doctype through serialization" do
      xml = '<!DOCTYPE root><root/>'
      doc = context.parse(xml)
      expect(doc.to_xml).to include("DOCTYPE")
      expect(doc.to_xml).to include("root")
    end
  end

  describe "round-trip stability" do
    it "round-trips a document with mixed content" do
      xml = <<~XML.strip
        <root attr="value">
          <child>text</child>
          <!-- comment -->
          <nested><deep>data</deep></nested>
        </root>
      XML

      doc1 = context.parse(xml)
      serialized1 = doc1.to_xml
      doc2 = context.parse(serialized1)
      serialized2 = doc2.to_xml

      expect(serialized2).to eq(serialized1)
    end

    it "round-trips a document with namespaces" do
      xml = '<root xmlns:ns="http://example.com/ns"><ns:child>content</ns:child></root>'
      doc1 = context.parse(xml)
      serialized1 = doc1.to_xml

      doc2 = context.parse(serialized1)
      child = doc2.root.children.find { |c| c.is_a?(Moxml::Element) }
      expect(child.name).to eq("child")
      expect(child.namespace_prefix).to eq("ns")
      expect(doc2.to_xml).to include("xmlns:ns")
    end

    it "round-trips a document with CDATA" do
      xml = '<root><![CDATA[<unparsed>content</unparsed>]]></root>'
      doc1 = context.parse(xml)
      serialized1 = doc1.to_xml

      expect(serialized1).to include("<![CDATA[")
      doc2 = context.parse(serialized1)
      expect(doc2.to_xml).to include("<![CDATA[")
    end
  end

  describe "XPath under Opal" do
    it "evaluates element-only XPath" do
      doc = context.parse("<root><a><b>1</b></a><a><b>2</b></a></root>")
      results = doc.xpath("//a/b")
      expect(results.length).to eq(2)
      expect(results.map(&:text)).to eq(%w[1 2])
    end

    it "supports attribute predicates" do
      doc = context.parse('<root><item id="x">1</item><item id="y">2</item></root>')
      found = doc.xpath("//item").find { |i| i["id"] == "y" }
      expect(found.text).to eq("2")
    end

    it "supports at_xpath" do
      doc = context.parse("<root><a>1</a><a>2</a></root>")
      first = doc.at_xpath("//a")
      expect(first.text).to eq("1")
    end
  end

  describe "comment and processing instruction handling" do
    it "preserves comments through parse/serialize" do
      xml = "<root><!-- my comment --></root>"
      doc = context.parse(xml)
      expect(doc.to_xml).to include("my comment")
    end

    it "preserves processing instructions through parse/serialize" do
      xml = '<?pi-target pi-data?><root/>'
      doc = context.parse(xml)
      expect(doc.to_xml).to include("pi-target")
    end
  end
end
