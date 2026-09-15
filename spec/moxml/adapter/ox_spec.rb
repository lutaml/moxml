# frozen_string_literal: true

require "moxml/adapter/ox"

RSpec.describe Moxml::Adapter::Ox do
  around do |example|
    Moxml.with_config(:ox, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

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

    describe "parse whitespace policy" do
      it "preserves whitespace runs inside text content by default (issue #189)" do
        doc = described_class.parse(%(<r xml:space="preserve"><t>  spaced  </t></r>))
        expect(doc.root.children.first.text).to eq("  spaced  ")
      end

      it "collapses runs with a per-parse ox_skip: :skip_white" do
        doc = described_class.parse(%(<r><t>  spaced  </t></r>), ox_skip: :skip_white)
        expect(doc.root.children.first.text).to eq(" spaced ")
      end

      it "honors a context default set once on the config" do
        context = Moxml.new(:ox) { |c| c.ox_skip = :skip_white }
        doc = context.parse(%(<r><t>  s  </t></r>))
        expect(doc.root.children.first.text).to eq(" s ")
      end

      it "lets a per-parse option beat the context default" do
        context = Moxml.new(:ox) { |c| c.ox_skip = :skip_white }
        doc = context.parse(%(<r><t>  s  </t></r>), ox_skip: :skip_none)
        expect(doc.root.children.first.text).to eq("  s  ")
      end

      it "fails loudly on ox_mode: :hash (the adapter walks a tree, not a Hash)" do
        expect { described_class.parse("<r><t> x </t></r>", ox_mode: :hash) }
          .to raise_error(RuntimeError, /must be a String or Ox::Node/)
      end

      it "surfaces an invalid ox_skip as Moxml::ParseError" do
        expect { described_class.parse("<r/>", ox_skip: :bogus) }
          .to raise_error(Moxml::ParseError)
      end

      it "validates Config ox_skip/ox_mode assignments" do
        expect { Moxml::Config.new.ox_skip = :bogus }
          .to raise_error(ArgumentError, /Invalid ox_skip/)
        expect { Moxml::Config.new.ox_mode = :bogus }
          .to raise_error(ArgumentError, /Invalid ox_mode/)
      end
    end
  end
end
