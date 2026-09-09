# frozen_string_literal: true

require "moxml/adapter/ox"

RSpec.describe Moxml::Adapter::Ox do
  around do |example|
    Moxml.with_config(:ox, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "parse tuning (ox_skip / ox_mode)" do
    let(:xml) { '<a xml:space="preserve">  spaced  </a>' }

    it "defaults to :skip_none so whitespace runs survive" do
      expect(Moxml.new(:ox).parse(xml).root.text).to eq("  spaced  ")
    end

    it "honours Config::OX_DEFAULT_SKIP as the default" do
      expect(Moxml::Config::OX_DEFAULT_SKIP).to eq(:skip_none)
      expect(Moxml::Config::OX_DEFAULT_MODE).to eq(:generic)
    end

    it "accepts a per-parse ox_skip override" do
      result = Moxml.new(:ox).parse(xml, ox_skip: :skip_white)

      expect(result.root.text).to eq(" spaced ")
    end

    it "accepts a context-level ox_skip default" do
      context = Moxml.new(:ox)
      context.config.ox_skip = :skip_white

      expect(context.parse(xml).root.text).to eq(" spaced ")
    end

    it "lets a per-parse ox_skip override the context default" do
      context = Moxml.new(:ox)
      context.config.ox_skip = :skip_white

      expect(context.parse(xml, ox_skip: :skip_none).root.text)
        .to eq("  spaced  ")
    end

    it "passes ox_mode through to Ox" do
      # :generic is the only mode yielding the node tree the adapter walks;
      # other modes are the caller's to choose, and fail loudly.
      expect { Moxml.new(:ox).parse(xml, ox_mode: :hash) }
        .to raise_error(StandardError)
    end

    it "surfaces an invalid ox_skip as a parse error naming the valid modes" do
      expect { Moxml.new(:ox).parse(xml, ox_skip: :nonsense) }
        .to raise_error(Moxml::ParseError, /skip_none/)
    end
  end

  describe "node_type" do
    it "returns :namespace for CustomizedOx::Namespace nodes" do
      element = described_class.create_native_element("test")
      ns = described_class.create_native_namespace(element, "ns", "http://example.com")
      expect(described_class.node_type(ns)).to eq(:namespace)
    end
  end

  describe "text handling" do
    let(:doc) { described_class.create_document }
    let(:element) { described_class.create_native_element("test") }

    it "creates text nodes as strings" do
      text = described_class.create_native_text("content")
      expect(text).to be_a(String)
      expect(text).to eq("content")
    end

    it "adds text nodes to elements" do
      text = described_class.create_native_text("content")
      described_class.add_child(element, text)
      expect(element.nodes.first).to eq("content")
    end
  end

  describe "xpath support" do
    let(:doc) do
      described_class.parse("<root><child id='1'>text</child><child id='2'>more</child></root>").native
    end

    it "supports basic element matching" do
      nodes = described_class.xpath(doc, "//child")
      expect(nodes.size).to eq(2)
      expect(nodes.first.name).to eq("child")
    end

    it "supports attribute value predicates" do
      nodes = described_class.xpath(doc, "//child[@id='1']")
      expect(nodes.size).to eq(1)
      expect(nodes.first.attributes[:id]).to eq("1")
    end

    it "supports logical operators" do
      nodes = described_class.xpath(doc, "//child[@id='1' or @id='2']")
      expect(nodes.size).to eq(2)
    end

    it "supports position predicates" do
      nodes = described_class.xpath(doc, "//child[2]")
      expect(nodes.size).to eq(1)
      expect(nodes.first.attributes[:id]).to eq("2")
    end

    it "supports XPath functions" do
      count = described_class.xpath(doc, "count(//child)")
      expect(count).to eq(2)
    end
  end
end
