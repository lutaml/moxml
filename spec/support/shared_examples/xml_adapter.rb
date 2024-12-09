RSpec.shared_examples "xml adapter" do
  let(:xml) do
    <<~XML
      <?xml version="1.0"?>
      <root xmlns="http://example.org" xmlns:x="http://example.org/x">
        <child id="1">Text</child>
        <child id="2"/>
        <x:special>
          <![CDATA[Some <special> text]]>
          <!-- A comment -->
          <?pi target?>
        </x:special>
      </root>
    XML
  end

  describe ".parse" do
    it "parses XML string" do
      doc = described_class.parse(xml)
      expect(described_class.node_type(doc)).to eq(:document)
      expect(described_class.node_name(described_class.root(doc))).to eq("root")
    end

    it "handles malformed XML according to strict setting" do
      malformed = "<root><unclosed>"

      expect {
        described_class.parse(malformed, strict: true)
      }.to raise_error(Moxml::ParseError)

      expect {
        described_class.parse(malformed, strict: false)
      }.not_to raise_error
    end
  end

  describe "node creation" do
    let(:doc) { described_class.create_document }

    it "creates element" do
      element = described_class.create_element("test")
      expect(described_class.node_type(element)).to eq(:element)
      expect(described_class.node_name(element)).to eq("test")
    end

    it "creates text" do
      text = described_class.create_text("content")
      expect(described_class.node_type(text)).to eq(:text)
    end

    it "creates CDATA" do
      cdata = described_class.create_cdata("<content>")
      expect(described_class.node_type(cdata)).to eq(:cdata)
    end

    it "creates comment" do
      comment = described_class.create_comment("comment")
      expect(described_class.node_type(comment)).to eq(:comment)
    end

    it "creates processing instruction" do
      pi = described_class.create_processing_instruction("target", "content")
      expect(described_class.node_type(pi)).to eq(:processing_instruction)
    end
  end

  describe "node manipulation" do
    let(:doc) { described_class.parse(xml) }
    let(:root) { described_class.root(doc) }

    it "gets parent" do
      child = described_class.children(root).first
      expect(described_class.parent(child)).to eq(root)
    end

    it "gets children" do
      children = described_class.children(root)
      expect(children.length).to eq(3)
    end

    it "gets siblings" do
      children = described_class.children(root)
      first = children[0]
      second = children[1]

      expect(described_class.next_sibling(first)).to eq(second)
      expect(described_class.previous_sibling(second)).to eq(first)
    end

    it "adds child" do
      element = described_class.create_element("new")
      described_class.add_child(root, element)
      expect(described_class.children(root).last).to eq(element)
    end

    it "adds text child" do
      described_class.add_child(root, "text")
      expect(described_class.children(root).last).to eq("text")
    end
  end

  describe "attributes" do
    let(:doc) { described_class.parse(xml) }
    let(:element) { described_class.children(described_class.root(doc)).first }

    it "gets attributes" do
      attrs = described_class.attributes(element)
      expect(attrs["id"]).to eq("1")
    end

    it "sets attribute" do
      described_class.set_attribute(element, "new", "value")
      expect(described_class.get_attribute(element, "new")).to eq("value")
    end

    it "removes attribute" do
      described_class.remove_attribute(element, "id")
      expect(described_class.get_attribute(element, "id")).to be_nil
    end

    it "handles special characters in attributes" do
      described_class.set_attribute(element, "special", '< > & " \'')
      value = described_class.get_attribute(element, "special")
      expect(value).to match(/&lt; &gt; &amp; (&quot;|") ('|&apos;)/)
    end
  end

  describe "namespaces" do
    let(:doc) { described_class.parse(xml) }
    let(:root) { described_class.root(doc) }
    let(:special) { described_class.children(root).last }

    it "creates namespace" do
      ns = described_class.create_namespace("test", "http://test.org")
      expect(ns).not_to be_nil
    end

    it "handles namespaced elements" do
      expect(described_class.node_name(special)).to eq("special")
    end
  end

  describe "serialization" do
    let(:doc) { described_class.parse(xml) }

    it "serializes to XML" do
      result = described_class.serialize(doc)
      expect(result).to include("<?xml")
      expect(result).to include("<root")
      expect(result).to include("</root>")
    end

    it "respects indentation settings" do
      unindented = described_class.serialize(doc, indent: -1)
      indented = described_class.serialize(doc, indent: 2)

      expect(unindented).not_to include("\n  ")
      expect(indented).to include("\n  ")
    end

    it "preserves XML declaration" do
      result = described_class.serialize(doc)
      expect(result).to match(/^<\?xml/)
    end

    it "handles encoding specification" do
      result = described_class.serialize(doc, encoding: "UTF-8")
      expect(result).to include('encoding="UTF-8"')
    end
  end

  describe "xpath" do
    let(:doc) { described_class.parse(xml) }

    it "finds nodes by xpath" do
      nodes = described_class.xpath(doc, "//child")
      expect(nodes.length).to eq(2)
    end

    it "finds first node by xpath" do
      node = described_class.at_xpath(doc, "//child")
      expect(described_class.get_attribute(node, "id")).to eq("1")
    end
  end
end
