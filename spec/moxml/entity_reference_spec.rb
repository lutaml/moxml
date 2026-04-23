# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "entity reference node" do |adapter_name|
  context "with #{adapter_name} adapter", adapter: adapter_name do
    let(:ctx) { Moxml.new(adapter_name) }

    describe "creating entity references" do
      it "creates an entity reference node" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("nbsp")
        expect(ref).to be_a(Moxml::EntityReference)
        expect(ref.name).to eq("nbsp")
      end

      it "creates standard XML entity references" do
        doc = ctx.create_document
        %w[amp lt gt quot apos].each do |name|
          ref = doc.create_entity_reference(name)
          expect(ref.name).to eq(name)
        end
      end

      it "raises ValidationError for invalid names" do
        doc = ctx.create_document
        expect do
          doc.create_entity_reference("123invalid")
        end.to raise_error(Moxml::ValidationError)
      end

      it "raises ValidationError for empty name" do
        doc = ctx.create_document
        expect do
          doc.create_entity_reference("")
        end.to raise_error(Moxml::ValidationError)
      end
    end

    describe "node properties" do
      it "has empty text content" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("amp")
        expect(ref.text).to eq("")
        expect(ref.content).to eq("")
      end

      it "is recognized as entity_reference type" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("copy")
        expect(ref.entity_reference?).to be true
      end
    end

    describe "serialization" do
      it "serializes to entity syntax" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("mdash")
        expect(ref.to_xml).to eq("&mdash;")
      end

      it "serializes standard entities" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("amp")
        expect(ref.to_xml).to eq("&amp;")
      end
    end

    describe "adding to document" do
      it "survives add_child and retrieval" do
        doc = ctx.create_document
        root = doc.create_element("p")
        doc.root = root
        ref = doc.create_entity_reference("nbsp")
        root.add_child(ref)
        children = root.children
        expect(children.size).to be >= 1
        entity_child = children.find { |c| c.is_a?(Moxml::EntityReference) }
        expect(entity_child).not_to be_nil
        expect(entity_child.name).to eq("nbsp")
      end

      it "serializes within a document" do
        doc = ctx.create_document
        root = doc.create_element("p")
        doc.root = root
        root.add_child(doc.create_text("before"))
        root.add_child(doc.create_entity_reference("nbsp"))
        root.add_child(doc.create_text("after"))
        output = doc.to_xml
        expect(output).to include("&nbsp;")
      end

      it "preserves multiple entity references in sequence" do
        doc = ctx.create_document
        root = doc.create_element("p")
        doc.root = root
        root.add_child(doc.create_entity_reference("nbsp"))
        root.add_child(doc.create_entity_reference("copy"))
        root.add_child(doc.create_entity_reference("mdash"))
        output = doc.to_xml
        expect(output).to include("&nbsp;")
        expect(output).to include("&copy;")
        expect(output).to include("&mdash;")
      end
    end
  end
end

RSpec.describe Moxml::EntityReference do
  %i[nokogiri oga ox rexml].each do |adapter_name|
    it_behaves_like "entity reference node", adapter_name
  end
end
