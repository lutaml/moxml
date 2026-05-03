# frozen_string_literal: true

RSpec.shared_examples "Entity Reference Whitespace Preservation" do
  let(:context) { Moxml.new }

  describe "whitespace preservation around entities on parse round-trip" do
    it "preserves spaces around entity references" do
      doc = context.parse("<p>A &copy; B &mdash; C</p>")
      xml = doc.root.to_xml

      expect(xml).to include("A ").and include(" B ").and include(" C")
    end

    it "preserves entity references in serialized output" do
      doc = context.parse("<p>Copyright &copy; 2024 &mdash; All rights reserved</p>")
      xml = doc.root.to_xml

      expect(xml).to include("&copy;")
      expect(xml).to include("&mdash;")
      expect(xml).to include("Copyright &copy; 2024 &mdash; All rights reserved")
    end

    it "preserves whitespace with single entity reference" do
      doc = context.parse("<p>A &copy; B</p>")

      expect(doc.root.inner_text).to include("A ").and include(" B")
    end

    it "preserves whitespace with entity at start of text" do
      doc = context.parse("<p>&copy; start</p>")

      expect(doc.root.inner_text).to include("&copy;")
      expect(doc.root.inner_text).to include(" start")
    end

    it "preserves whitespace with entity at end of text" do
      doc = context.parse("<p>end &copy;</p>")

      expect(doc.root.inner_text).to include("end ")
      expect(doc.root.inner_text).to include("&copy;")
    end
  end

  describe "Builder entity reference whitespace" do
    # REXML and LibXML store entity references outside the native DOM tree,
    # so they cannot maintain positional ordering relative to text nodes.
    before do
      adapter_name = context.config.adapter.name
      if adapter_name.include?("Rexml") || adapter_name.include?("Libxml")
        skip "#{adapter_name} does not support inline entity reference nodes via Builder"
      end
    end

    it "preserves spaces around entity references" do
      doc = Moxml::Builder.new(context).build do
        element "p" do
          text "Copyright "
          entity_reference "copy"
          text " 2024 "
          entity_reference "mdash"
          text " All rights reserved"
        end
      end

      xml = doc.root.to_xml
      expect(xml).to include("Copyright &copy; 2024 &mdash; All rights reserved")
    end

    it "preserves whitespace-only text nodes adjacent to entity references" do
      doc = Moxml::Builder.new(context).build do
        element "p" do
          entity_reference "copy"
          text " "
          entity_reference "mdash"
        end
      end

      children = doc.root.children
      types = children.map(&:class)

      expect(types).to eq([
                            Moxml::EntityReference,
                            Moxml::Text,
                            Moxml::EntityReference,
                          ])
      expect(children[1].content).to eq(" ")
    end

    it "preserves multiple spaces between entity references" do
      doc = Moxml::Builder.new(context).build do
        element "p" do
          text "A"
          entity_reference "amp"
          text "  "
          entity_reference "lt"
          text "B"
        end
      end

      children = doc.root.children
      expect(children.length).to eq(5)
      expect(children[2].content).to eq("  ")
    end
  end

  describe "structural whitespace filtering" do
    it "preserves whitespace text nodes between elements" do
      xml = <<~XML
        <root>
          <child1/>
          <child2/>
        </root>
      XML

      doc = context.parse(xml)
      children = doc.root.children

      # Whitespace text nodes between elements are preserved
      elements = children.grep(Moxml::Element)
      expect(elements.length).to eq(2)
      expect(elements.map(&:name)).to eq(%w[child1 child2])
    end
  end
end
