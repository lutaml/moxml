# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Entity preservation across adapters" do
  shared_examples "consistent entity handling" do
    describe "text content with entities" do
      it "preserves single entity in inner_text" do
        doc = adapter.parse("<root>&copy; 2024</root>")
        expect(doc.root.inner_text).to eq("&copy; 2024")
      end

      it "preserves multiple entities in inner_text" do
        doc = adapter.parse("<root>&copy; text &mdash; end</root>")
        expect(doc.root.inner_text).to eq("&copy; text &mdash; end")
      end

      it "preserves entity at start" do
        doc = adapter.parse("<root>&copy; start</root>")
        expect(doc.root.inner_text).to include("&copy;")
      end

      it "preserves entity at end" do
        doc = adapter.parse("<root>end &copy;</root>")
        expect(doc.root.inner_text).to include("&copy;")
      end

      it "does not alter standard entities" do
        doc = adapter.parse("<root>&amp; &lt; &gt;</root>")
        expect(doc.root.inner_text).to eq("& < >")
      end
    end

    describe "to_xml round-trip" do
      it "preserves entity in serialized output" do
        doc = adapter.parse("<root>&copy; 2024</root>")
        expect(doc.root.to_xml(declaration: false)).to include("&copy;")
      end

      it "preserves multiple entities in serialized output" do
        doc = adapter.parse("<root>&copy; text &mdash; end</root>")
        xml = doc.root.to_xml(declaration: false)
        expect(xml).to include("&copy;")
        expect(xml).to include("&mdash;")
      end

      it "does not double-escape standard entities" do
        doc = adapter.parse("<root>&amp; test</root>")
        xml = doc.root.to_xml(declaration: false)
        expect(xml).to include("&amp;")
        expect(xml).not_to include("&amp;amp;")
      end
    end

    describe "attribute values with entities" do
      it "preserves entity in attribute value" do
        doc = adapter.parse('<root attr="&copy; 2024"/>')
        expect(doc.root["attr"]).to eq("&copy; 2024")
      end

      it "preserves entity in attribute via Attribute#value" do
        doc = adapter.parse('<root attr="&copy; 2024"/>')
        attr = doc.root.attributes.first
        expect(attr.value).to eq("&copy; 2024")
      end

      it "preserves entity in attribute to_xml" do
        doc = adapter.parse('<root attr="&copy; 2024"/>')
        xml = doc.root.to_xml(declaration: false)
        expect(xml).to include('attr="&copy; 2024"')
      end
    end

    describe "Text node content" do
      it "preserves entity in Text#content" do
        doc = adapter.parse("<root>&copy; text</root>")
        text_nodes = doc.root.children.grep(Moxml::Text)
        combined = text_nodes.map(&:content).join
        expect(combined).to include("&copy;")
      end
    end
  end

  context "with nokogiri adapter" do
    let(:adapter) { Moxml::Adapter::Nokogiri }

    before { require "moxml/adapter/nokogiri" }

    it_behaves_like "consistent entity handling"
  end

  context "with oga adapter" do
    let(:adapter) { Moxml::Adapter::Oga }

    before { require "moxml/adapter/oga" }

    it_behaves_like "consistent entity handling"
  end

  context "with rexml adapter" do
    let(:adapter) { Moxml::Adapter::Rexml }

    before { require "moxml/adapter/rexml" }

    it_behaves_like "consistent entity handling"
  end

  context "with ox adapter" do
    let(:adapter) { Moxml::Adapter::Ox }

    before { require "moxml/adapter/ox" }

    it_behaves_like "consistent entity handling"
  end
end
