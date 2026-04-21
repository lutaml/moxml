# frozen_string_literal: true

require "oga"
require "moxml/adapter/oga"

RSpec.describe Moxml::Adapter::Oga do
  around do |example|
    Moxml.with_config(:oga, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "serialization" do
    it "does not duplicate XML declarations when declaration nodes repeat" do
      context = Moxml::Context.new(:oga)
      doc = context.create_document

      doc.add_child(doc.create_declaration("1.0", "UTF-8"))
      doc.add_child(doc.create_declaration("1.0", "UTF-8"))
      doc.add_child(doc.create_element("root"))

      serialized = doc.to_xml

      expect(serialized.scan("<?xml").size).to eq(1)
      expect(serialized).to include("<root></root>")
    end
  end

  describe "entity handling" do
    it "preserves non-breaking space through parse and serialize round-trip" do
      xml = "<root>Item&nbsp;One</root>"
      doc = described_class.parse(xml)
      serialized = doc.to_xml
      # After round-trip, the entity reference should be preserved
      expect(serialized).to include("&nbsp;")
      expect(serialized).to include("Item")
      expect(serialized).to include("One")
    end

    it "correctly parses numeric character references" do
      xml = "<root>&#160;</root>"
      doc = described_class.parse(xml)
      text = described_class.text_content(doc.at_xpath("//root"))

      # Should contain the actual non-breaking space character (U+00A0)
      expect(text.bytes).to include(160)
    end

    it "handles multiple different entities" do
      xml = "<root>&nbsp;&mdash;&lsquo;</root>"
      doc = described_class.parse(xml)
      serialized = doc.to_xml

      # All entities should be preserved in round-trip
      expect(serialized).to include("&nbsp;")
      expect(serialized).to include("&mdash;")
      expect(serialized).to include("&lsquo;")
    end

    it "preserves entities when creating text nodes programmatically" do
      context = Moxml::Context.new(:oga)
      doc = context.create_document
      root = doc.create_element("root")
      doc.add_child(root)
      text = doc.create_text("Hello&nbsp;World")
      root.add_child(text)

      serialized = doc.to_xml
      expect(serialized).to include("Hello&nbsp;World")
    end

    it "preserves entities when setting text content programmatically" do
      context = Moxml::Context.new(:oga)
      doc = context.create_document
      root = doc.create_element("root")
      doc.add_child(root)
      text = doc.create_text("placeholder")
      root.add_child(text)
      text.content = "Value&nbsp;Here"

      serialized = doc.to_xml
      expect(serialized).to include("Value&nbsp;Here")
    end

    it "preserves entities in attribute values through parse round-trip" do
      xml = '<root attr="one&nbsp;two"/>'
      doc = described_class.parse(xml)
      root_native = doc.at_xpath("//root")
      value = described_class.get_attribute_value(root_native, "attr")

      expect(value).to eq("one&nbsp;two")
    end

    it "preserves entities when setting attribute values programmatically" do
      context = Moxml::Context.new(:oga)
      doc = context.create_document
      root = doc.create_element("root")
      doc.add_child(root)
      root["data"] = "a&nbsp;b"

      serialized = doc.to_xml
      expect(serialized).to include('data="a&nbsp;b"')
    end

    it "does not marker-encode unknown entities in programmatic text" do
      # Unknown entities (not in W3C registry) are left as-is by encode_entity_markers.
      # Oga will drop them during serialization since they're not valid XML entities.
      context = Moxml::Context.new(:oga)
      doc = context.create_document
      root = doc.create_element("root")
      doc.add_child(root)
      text = doc.create_text("test&foo;bar")
      root.add_child(text)

      serialized = doc.to_xml
      # &foo; is not a known entity, so it won't survive Oga's serialization
      expect(serialized).not_to include("\x01")
    end
  end

  describe "doctype handling" do
    it "correctly parses PUBLIC doctype" do
      xml = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html/>'
      doc = described_class.parse(xml)
      doctype = doc.children.find { |c| c.is_a?(Moxml::Doctype) }

      expect(doctype.name).to eq("html")
      expect(doctype.external_id).to eq("-//W3C//DTD XHTML 1.0 Strict//EN")
      expect(doctype.system_id).to eq("http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")
    end

    it "correctly parses SYSTEM doctype" do
      xml = '<!DOCTYPE config SYSTEM "config.dtd"><config/>'
      doc = described_class.parse(xml)
      doctype = doc.children.find { |c| c.is_a?(Moxml::Doctype) }

      expect(doctype.name).to eq("config")
      expect(doctype.external_id).to be_nil
      expect(doctype.system_id).to eq("config.dtd")
    end

    it "correctly parses simple doctype" do
      xml = "<!DOCTYPE html><html/>"
      doc = described_class.parse(xml)
      doctype = doc.children.find { |c| c.is_a?(Moxml::Doctype) }

      expect(doctype.name).to eq("html")
      expect(doctype.external_id).to be_nil
      expect(doctype.system_id).to be_nil
    end

    it "round-trips PUBLIC doctype" do
      xml = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html/>'
      doc = described_class.parse(xml)

      expect(doc.to_xml).to include('PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"')
    end

    it "round-trips SYSTEM doctype" do
      xml = '<!DOCTYPE config SYSTEM "config.dtd"><config/>'
      doc = described_class.parse(xml)

      expect(doc.to_xml).to include('SYSTEM "config.dtd"')
    end
  end
end
