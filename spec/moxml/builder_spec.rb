# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Builder do
  let(:context) { Moxml.new }

  describe "#document" do
    it "exposes the underlying document via document accessor" do
      builder = described_class.new(context)
      expect(builder.document).to be_a(Moxml::Document)
    end

    it "exposes the underlying document via doc alias" do
      builder = described_class.new(context)
      expect(builder.doc).to be_a(Moxml::Document)
      expect(builder.doc).to equal(builder.document)
    end

    it "returns the same document before and after build" do
      builder = described_class.new(context)
      doc_before = builder.document
      builder.build do
        element "root"
      end
      expect(builder.document).to equal(doc_before)
    end
  end

  describe "#build" do
    it "builds a document with DSL" do
      doc = described_class.new(context).build do
        element "root" do
          element "child" do
            text "text"
          end
        end
      end

      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end

    it "creates nested elements" do
      doc = described_class.new(context).build do
        element "parent" do
          element "child1"
          element "child2"
        end
      end

      expect(doc.root.children.length).to eq(2)
    end
  end

  describe "#element with no arguments" do
    it "raises ArgumentError" do
      builder = described_class.new(context)
      expect do
        builder.build { element }
      end.to raise_error(ArgumentError, "element requires a tag name")
    end
  end

  describe "#element with Hash (tag name collision)" do
    it "creates an <element> tag when called with a Hash" do
      doc = described_class.new(context).build do
        element(name: "foo", type: "bar")
      end

      el = doc.root
      expect(el.name).to eq("element")
      expect(el["name"]).to eq("foo")
      expect(el["type"]).to eq("bar")
    end
  end

  describe "method_missing DSL" do
    it "creates elements via bare method calls inside build block" do
      doc = described_class.new(context).build do
        root do
          title("Hello")
        end
      end

      expect(doc.root.name).to eq("root")
      expect(doc.root.children.first.name).to eq("title")
      expect(doc.root.children.first.text).to eq("Hello")
    end

    it "creates elements via explicit receiver" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.title("Hello")
        end
      end

      title_el = doc.root.children.first
      expect(title_el.name).to eq("title")
      expect(title_el.text).to eq("Hello")
    end

    it "creates elements with attributes" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.item(id: "1", class: "active")
        end
      end

      item_el = doc.root.children.first
      expect(item_el.name).to eq("item")
      expect(item_el["id"]).to eq("1")
      expect(item_el["class"]).to eq("active")
    end

    it "creates elements with both text content and attributes" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.title("Hello", lang: "en")
        end
      end

      title_el = doc.root.children.first
      expect(title_el.name).to eq("title")
      expect(title_el.text).to eq("Hello")
      expect(title_el["lang"]).to eq("en")
    end

    it "creates nested elements with blocks" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.parent do
            builder.child("text")
          end
        end
      end

      parent_el = doc.root.children.first
      expect(parent_el.name).to eq("parent")
      child_el = parent_el.children.first
      expect(child_el.name).to eq("child")
      expect(child_el.text).to eq("text")
    end

    it "creates elements with namespace attributes" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.schema(xmlns: "http://www.w3.org/2001/XMLSchema")
        end
      end

      schema_el = doc.root.children.first
      expect(schema_el.name).to eq("schema")
    end
  end

  describe "trailing underscore stripping (special tags)" do
    it "strips trailing underscore to allow reserved method names as tags" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.type_("Object")
          builder.class_("String")
          builder.id_("42")
        end
      end

      children = doc.root.children
      expect(children[0].name).to eq("type")
      expect(children[0].text).to eq("Object")
      expect(children[1].name).to eq("class")
      expect(children[1].text).to eq("String")
      expect(children[2].name).to eq("id")
      expect(children[2].text).to eq("42")
    end

    it "strips trailing underscore with attributes" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.type_(name: "foo")
        end
      end

      el = doc.root.children.first
      expect(el.name).to eq("type")
      expect(el["name"]).to eq("foo")
    end

    it "strips trailing underscore with block" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.class_ do
            builder.name_("MyClass")
          end
        end
      end

      class_el = doc.root.children.first
      expect(class_el.name).to eq("class")
      expect(class_el.children.first.name).to eq("name")
    end

    it "works with bare method calls inside build block" do
      doc = described_class.new(context).build do
        root do
          type_("Object")
        end
      end

      expect(doc.root.children.first.name).to eq("type")
      expect(doc.root.children.first.text).to eq("Object")
    end

    it "does not strip underscore from middle of name" do
      builder = described_class.new(context)
      doc = builder.build do
        element "root" do
          builder.my_element("text")
        end
      end

      expect(doc.root.children.first.name).to eq("my_element")
    end
  end

  describe "respond_to_missing?" do
    it "returns true for arbitrary element names" do
      builder = described_class.new(context)
      expect(builder.respond_to?(:schema)).to be true
      expect(builder.respond_to?(:custom_element)).to be true
    end

    it "returns false for reserved Ruby conversion and protocol methods" do
      builder = described_class.new(context)
      expect(builder.respond_to?(:to_ary)).to be false
      expect(builder.respond_to?(:to_hash)).to be false
      expect(builder.respond_to?(:to_str)).to be false
      expect(builder.respond_to?(:to_xml)).to be false
    end
  end

  describe "method_missing argument validation" do
    it "raises ArgumentError for unexpected extra arguments" do
      builder = described_class.new(context)
      expect do
        builder.build do
          element "root" do
            builder.foo("text", { id: "1" }, "extra")
          end
        end
      end.to raise_error(ArgumentError, /unexpected arguments for foo/)
    end

    it "raises ArgumentError when combining text content with a block" do
      builder = described_class.new(context)
      expect do
        builder.build do
          element "root" do
            builder.title("Hello") { builder.child }
          end
        end
      end.to raise_error(ArgumentError,
                         /title: cannot combine text content with a block/)
    end
  end

  describe "#entity_reference" do
    it "creates entity references via DSL" do
      doc = described_class.new(context).build do
        element "p" do
          entity_reference "nbsp"
        end
      end
      ref = doc.root.children.first
      expect(ref).to be_a(Moxml::EntityReference)
      expect(ref.name).to eq("nbsp")
      expect(doc.to_xml).to include("&nbsp;")
    end
  end

  describe "@current restoration on error" do
    it "restores @current when block raises" do
      builder = described_class.new(context)
      expect do
        builder.build do
          element "root" do
            element "child" do
              raise "test error"
            end
          end
        end
      end.to raise_error(RuntimeError, "test error")

      expect(builder.instance_variable_get(:@current)).to equal(builder.document)
    end
  end
end
