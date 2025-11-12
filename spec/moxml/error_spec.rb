# frozen_string_literal: true

# spec/moxml/errors_spec.rb
RSpec.describe "Moxml errors" do
  describe Moxml::Error do
    it "is a StandardError" do
      expect(described_class.new).to be_a(StandardError)
    end
  end

  describe Moxml::ParseError do
    it "includes line and column information" do
      error = described_class.new("Invalid XML", line: 5, column: 10)
      expect(error.line).to eq(5)
      expect(error.column).to eq(10)
      # The base message should be unchanged
      expect(error.message).to include("Invalid XML")
    end

    it "works without line and column" do
      error = described_class.new("Invalid XML")
      expect(error.line).to be_nil
      expect(error.column).to be_nil
    end

    it "includes source context" do
      error = described_class.new("Invalid XML", source: "<invalid>")
      expect(error.source).to eq("<invalid>")
    end

    it "provides helpful error message with context" do
      error = described_class.new("Invalid XML", line: 5, column: 10)
      message = error.to_s
      expect(message).to include("Invalid XML")
      expect(message).to include("Line: 5")
      expect(message).to include("Column: 10")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::XPathError do
    it "includes expression and adapter information" do
      error = described_class.new(
        "Invalid XPath",
        expression: "//invalid[",
        adapter: "Nokogiri",
      )
      expect(error.expression).to eq("//invalid[")
      expect(error.adapter).to eq("Nokogiri")
    end

    it "provides helpful error message" do
      error = described_class.new(
        "Invalid XPath",
        expression: "//test",
        adapter: "REXML",
      )
      message = error.to_s
      expect(message).to include("Invalid XPath")
      expect(message).to include("Expression: //test")
      expect(message).to include("Adapter: REXML")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::ValidationError do
    it "includes node, constraint, and value information" do
      error = described_class.new(
        "Invalid version",
        constraint: "version",
        value: "2.0",
      )
      expect(error.constraint).to eq("version")
      expect(error.value).to eq("2.0")
    end

    it "provides helpful error message" do
      error = described_class.new(
        "Invalid encoding",
        constraint: "encoding",
        value: "INVALID",
      )
      message = error.to_s
      expect(message).to include("Invalid encoding")
      expect(message).to include("Constraint: encoding")
      expect(message).to include("Value: \"INVALID\"")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::NamespaceError do
    it "includes prefix, uri, and element information" do
      error = described_class.new(
        "Invalid namespace",
        prefix: "ns",
        uri: "http://example.com",
      )
      expect(error.prefix).to eq("ns")
      expect(error.uri).to eq("http://example.com")
      expect(error.message).to eq("Invalid namespace")
    end

    it "provides access to error attributes" do
      error = described_class.new(
        "Invalid namespace",
        prefix: "ns",
        uri: "invalid-uri",
      )
      expect(error.message).to include("Invalid namespace")
      expect(error.prefix).to eq("ns")
      expect(error.uri).to eq("invalid-uri")
    end
  end

  describe Moxml::AdapterError do
    it "includes adapter name and operation" do
      error = described_class.new(
        "Failed to load adapter",
        adapter: "nokogiri",
        operation: "load",
      )
      expect(error.adapter_name).to eq("nokogiri")
      expect(error.operation).to eq("load")
    end

    it "includes native error information" do
      native_err = StandardError.new("Gem not found")
      error = described_class.new(
        "Failed to load adapter",
        adapter: "nokogiri",
        native_error: native_err,
      )
      expect(error.native_error).to eq(native_err)
    end

    it "provides helpful error message" do
      native_err = LoadError.new("cannot load such file")
      error = described_class.new(
        "Failed to load adapter",
        adapter: "oga",
        operation: "require",
        native_error: native_err,
      )
      message = error.to_s
      expect(message).to include("Failed to load adapter")
      expect(message).to include("Adapter: oga")
      expect(message).to include("Operation: require")
      expect(message).to include("Native Error: LoadError")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::SerializationError do
    it "includes node, adapter, and format information" do
      error = described_class.new(
        "Failed to serialize",
        adapter: "LibXML",
        format: "xml",
      )
      expect(error.adapter).to eq("LibXML")
      expect(error.format).to eq("xml")
    end

    it "provides helpful error message" do
      error = described_class.new(
        "Failed to serialize",
        adapter: "Ox",
        format: "xml",
      )
      message = error.to_s
      expect(message).to include("Failed to serialize")
      expect(message).to include("Adapter: Ox")
      expect(message).to include("Format: xml")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::DocumentStructureError do
    it "includes attempted operation and state" do
      error = described_class.new(
        "Invalid operation",
        operation: "add_child",
        state: "no_root",
      )
      expect(error.attempted_operation).to eq("add_child")
      expect(error.current_state).to eq("no_root")
    end

    it "provides helpful error message" do
      error = described_class.new(
        "Invalid operation",
        operation: "set_root",
        state: "root_already_exists",
      )
      message = error.to_s
      expect(message).to include("Invalid operation")
      expect(message).to include("Operation: set_root")
      expect(message).to include("Current State: root_already_exists")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::AttributeError do
    it "includes attribute name, element, and value" do
      error = described_class.new(
        "Invalid attribute",
        name: "id",
        value: 123,
      )
      expect(error.attribute_name).to eq("id")
      expect(error.value).to eq(123)
    end

    it "provides helpful error message" do
      error = described_class.new(
        "Invalid attribute name",
        name: "123invalid",
        value: "test",
      )
      message = error.to_s
      expect(message).to include("Invalid attribute name")
      expect(message).to include("Attribute: 123invalid")
      expect(message).to include("Value: \"test\"")
      expect(message).to include("Hint:")
    end
  end

  describe Moxml::NotImplementedError do
    it "includes feature and adapter information" do
      error = described_class.new(
        "Feature not supported",
        feature: "xpath",
        adapter: "CustomAdapter",
      )
      expect(error.feature).to eq("xpath")
      expect(error.adapter).to eq("CustomAdapter")
    end

    it "provides helpful error message" do
      error = described_class.new(
        "Feature not supported",
        feature: "namespaces",
        adapter: "MinimalAdapter",
      )
      message = error.to_s
      expect(message).to include("Feature not supported")
      expect(message).to include("Feature: namespaces")
      expect(message).to include("Adapter: MinimalAdapter")
      expect(message).to include("Hint:")
    end

    it "has a default message" do
      error = described_class.new
      expect(error.message).to include("Feature not implemented")
    end
  end

  describe "error handling in context" do
    let(:context) { Moxml.new }

    it "raises ParseError for invalid XML with enhanced context" do
      expect do
        context.parse("<invalid>", strict: true)
      end.to raise_error(Moxml::ParseError) do |error|
        expect(error.to_s).to include("Hint:")
      end
    end

    it "raises XPathError for invalid XPath with enhanced context" do
      doc = context.parse("<root/>")
      expect do
        doc.xpath("///")
      end.to raise_error(Moxml::XPathError) do |error|
        expect(error.expression).to eq("///")
        expect(error.to_s).to include("Hint:")
      end
    end

    it "raises NamespaceError for invalid namespace with enhanced context" do
      doc = context.parse("<root/>")

      expect do
        doc.root.add_namespace("xml", "http//invalid.com")
      end.to raise_error(Moxml::NamespaceError) do |error|
        expect(error.uri).to eq("http//invalid.com")
        expect(error.prefix).to eq("xml")
        expect(error.message).to include("Invalid URI")
      end
    end

    it "raises ValidationError for invalid XML constructs" do
      expect do
        context.parse('<?xml version="2.0"?><root/>', strict: true)
      end.to raise_error(Moxml::ParseError)
    end

    it "raises AdapterError for invalid adapter configuration" do
      expect do
        Moxml::Config.new.adapter = :invalid_adapter
      end.to raise_error(Moxml::AdapterError) do |error|
        expect(error.adapter_name).to eq(:invalid_adapter)
        expect(error.to_s).to include("Hint:")
      end
    end

    it "raises DocumentStructureError for invalid node operations" do
      doc = context.parse("<root/>")
      expect do
        doc.root.add_child(Object.new)
      end.to raise_error(Moxml::DocumentStructureError) do |error|
        expect(error.to_s).to include("Hint:")
      end
    end
  end
end
