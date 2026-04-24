# frozen_string_literal: true

RSpec.shared_examples "Moxml::DocumentBuilder" do
  let(:context) { Moxml.new }
  let(:builder) { Moxml::DocumentBuilder.new(context) }

  describe "#build" do
    it "builds a document model from native document" do
      xml = "<root><child>text</child></root>"
      doc = context.config.adapter.parse(xml)

      expect(doc).to be_a(Moxml::Document)
      expect(doc.root).to be_a(Moxml::Element)
      expect(doc.root.name).to eq("root")
      expect(doc.root.children.first).to be_a(Moxml::Element)
      expect(doc.root.children.first.text).to eq("text")
    end

    it "handles complex documents" do
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <root xmlns="http://example.org">
          <!-- comment -->
          <child id="1">
            <![CDATA[cdata content]]>
          </child>
          <?pi target data?>
        </root>
      XML

      doc = context.config.adapter.parse(xml)

      expect(doc.root.namespaces.count).to eq(1)
      expect(doc.root.namespaces.first.uri).to eq("http://example.org")
      # Whitespace text nodes are preserved between elements
      non_ws_children = doc.root.children.reject { |c| c.is_a?(Moxml::Text) && c.content.strip.empty? }
      expect(non_ws_children[0]).to be_a(Moxml::Comment)
      expect(non_ws_children[1]).to be_a(Moxml::Element)
      expect(non_ws_children[1].name).to eq("child")
      expect(non_ws_children[1]["id"]).to eq("1")
      expect(non_ws_children[1].children.find { |c| c.is_a?(Moxml::Cdata) }).to be_a(Moxml::Cdata)
      expect(non_ws_children[2]).to be_a(Moxml::ProcessingInstruction)
    end
  end
end
