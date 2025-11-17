# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Conversion do
  let(:context) { Moxml.new }

  describe ".to_string" do
    it "converts integers to strings" do
      expect(described_class.to_string(42)).to eq("42")
    end

    it "converts floats with zero decimal to integers first" do
      expect(described_class.to_string(10.0)).to eq("10")
    end

    it "preserves non-zero decimals in floats" do
      expect(described_class.to_string(10.5)).to eq("10.5")
    end

    it "converts strings to themselves" do
      expect(described_class.to_string("hello")).to eq("hello")
    end

    it "converts true to string" do
      expect(described_class.to_string(true)).to eq("true")
    end

    it "converts false to string" do
      expect(described_class.to_string(false)).to eq("false")
    end

    it "converts nil to empty string" do
      expect(described_class.to_string(nil)).to eq("")
    end

    context "with NodeSet" do
      it "returns text of first node" do
        doc = context.parse("<root><item>first</item><item>second</item></root>")
        nodes = doc.xpath("//item")

        expect(described_class.to_string(nodes)).to eq("first")
      end

      it "returns empty string for empty NodeSet" do
        doc = context.parse("<root></root>")
        nodes = doc.xpath("//item")

        expect(described_class.to_string(nodes)).to eq("")
      end
    end

    context "with nodes that respond to text" do
      it "returns the text content of the node" do
        doc = context.parse("<root>Hello World</root>")
        node = doc.xpath("//root").first

        expect(described_class.to_string(node)).to eq("Hello World")
      end
    end
  end

  describe ".to_float" do
    it "converts integers to floats" do
      expect(described_class.to_float(42)).to eq(42.0)
    end

    it "converts floats to themselves" do
      expect(described_class.to_float(10.5)).to eq(10.5)
    end

    it "converts numeric strings to floats" do
      expect(described_class.to_float("42.5")).to eq(42.5)
    end

    it "converts true to 1.0" do
      expect(described_class.to_float(true)).to eq(1.0)
    end

    it "converts false to 0.0" do
      expect(described_class.to_float(false)).to eq(0.0)
    end

    it "returns NaN for non-numeric strings" do
      result = described_class.to_float("not a number")
      expect(result).to be_nan
    end

    it "returns NaN for nil" do
      result = described_class.to_float(nil)
      expect(result).to be_nan
    end

    it "returns NaN for empty string" do
      result = described_class.to_float("")
      expect(result).to be_nan
    end

    context "with NodeSet" do
      it "converts text of first node to float" do
        doc = context.parse("<root><item>42.5</item></root>")
        nodes = doc.xpath("//item")

        expect(described_class.to_float(nodes)).to eq(42.5)
      end

      it "returns NaN for empty NodeSet" do
        doc = context.parse("<root></root>")
        nodes = doc.xpath("//item")

        result = described_class.to_float(nodes)
        expect(result).to be_nan
      end

      it "returns NaN for non-numeric node text" do
        doc = context.parse("<root><item>hello</item></root>")
        nodes = doc.xpath("//item")

        result = described_class.to_float(nodes)
        expect(result).to be_nan
      end
    end

    context "with nodes that respond to text" do
      it "converts node text to float" do
        doc = context.parse("<root>123.45</root>")
        node = doc.xpath("//root").first

        expect(described_class.to_float(node)).to eq(123.45)
      end
    end
  end

  describe ".to_boolean" do
    context "with floats" do
      it "returns true for positive floats" do
        expect(described_class.to_boolean(1.5)).to be(true)
      end

      it "returns false for zero" do
        expect(described_class.to_boolean(0.0)).to be(false)
      end

      it "returns true for negative floats" do
        expect(described_class.to_boolean(-1.5)).to be(true)
      end

      it "returns false for NaN" do
        expect(described_class.to_boolean(Float::NAN)).to be(false)
      end
    end

    context "with integers" do
      it "returns true for positive integers" do
        expect(described_class.to_boolean(42)).to be(true)
      end

      it "returns false for zero" do
        expect(described_class.to_boolean(0)).to be(false)
      end

      it "returns true for negative integers" do
        expect(described_class.to_boolean(-42)).to be(true)
      end
    end

    context "with strings" do
      it "returns true for non-empty strings" do
        expect(described_class.to_boolean("hello")).to be(true)
      end

      it "returns false for empty strings" do
        expect(described_class.to_boolean("")).to be(false)
      end
    end

    context "with arrays" do
      it "returns true for non-empty arrays" do
        expect(described_class.to_boolean([1, 2, 3])).to be(true)
      end

      it "returns false for empty arrays" do
        expect(described_class.to_boolean([])).to be(false)
      end
    end

    context "with NodeSets" do
      it "returns true for non-empty NodeSets" do
        doc = context.parse("<root><item/></root>")
        nodes = doc.xpath("//item")

        expect(described_class.to_boolean(nodes)).to be(true)
      end

      it "returns false for empty NodeSets" do
        doc = context.parse("<root></root>")
        nodes = doc.xpath("//item")

        expect(described_class.to_boolean(nodes)).to be(false)
      end
    end

    context "with true/false" do
      it "returns true for true" do
        expect(described_class.to_boolean(true)).to be(true)
      end

      it "returns false for false" do
        expect(described_class.to_boolean(false)).to be(false)
      end
    end

    context "with nil" do
      it "returns false for nil" do
        expect(described_class.to_boolean(nil)).to be(false)
      end
    end

    context "with other objects" do
      it "returns true for any truthy object" do
        expect(described_class.to_boolean(Object.new)).to be(true)
      end
    end
  end

  describe ".to_compatible_types" do
    it "converts NodeSet to string when compared with another value" do
      doc = context.parse("<root><item>hello</item></root>")
      nodes = doc.xpath("//item")

      left, right = described_class.to_compatible_types(nodes, "world")
      expect(left).to eq("hello")
      expect(right).to eq("world")
    end

    it "converts node to string when compared with another value" do
      doc = context.parse("<root>test</root>")
      node = doc.xpath("//root").first

      left, right = described_class.to_compatible_types(node, "other")
      expect(left).to eq("test")
      expect(right).to eq("other")
    end

    it "converts right operand to float when left is numeric" do
      left, right = described_class.to_compatible_types(42, "10")
      expect(left).to eq(42)
      expect(right).to eq(10.0)
    end

    it "converts right operand to string when left is string" do
      left, right = described_class.to_compatible_types("hello", 42)
      expect(left).to eq("hello")
      expect(right).to eq("42")
    end

    it "converts right operand to boolean when left is boolean" do
      left, right = described_class.to_compatible_types(true, "non-empty")
      expect(left).to be(true)
      expect(right).to be(true)
    end

    it "handles both NodeSets" do
      doc = context.parse("<root><a>text1</a><b>text2</b></root>")
      nodes1 = doc.xpath("//a")
      nodes2 = doc.xpath("//b")

      left, right = described_class.to_compatible_types(nodes1, nodes2)
      expect(left).to eq("text1")
      expect(right).to eq("text2")
    end

    it "preserves compatible types" do
      left, right = described_class.to_compatible_types(10, 20)
      expect(left).to eq(10)
      expect(right).to eq(20)
    end

    it "handles false boolean correctly" do
      left, right = described_class.to_compatible_types(false, "text")
      expect(left).to be(false)
      expect(right).to be(true)
    end
  end

  describe ".boolean?" do
    it "returns true for true" do
      expect(described_class.boolean?(true)).to be(true)
    end

    it "returns true for false" do
      expect(described_class.boolean?(false)).to be(true)
    end

    it "returns false for integers" do
      expect(described_class.boolean?(42)).to be(false)
    end

    it "returns false for strings" do
      expect(described_class.boolean?("true")).to be(false)
    end

    it "returns false for nil" do
      expect(described_class.boolean?(nil)).to be(false)
    end

    it "returns false for arrays" do
      expect(described_class.boolean?([true])).to be(false)
    end
  end

  describe ".first_node_text" do
    it "returns text of first node in NodeSet" do
      doc = context.parse("<root><item>first</item><item>second</item></root>")
      nodes = doc.xpath("//item")

      expect(described_class.first_node_text(nodes)).to eq("first")
    end

    it "returns empty string if first node does not respond to text" do
      # Create a mock NodeSet with a node that doesn't respond to text
      node_set = [double("node")]
      allow(node_set).to receive(:[]).with(0).and_return(node_set[0])

      expect(described_class.first_node_text(node_set)).to eq("")
    end

    it "handles nodes with empty text" do
      doc = context.parse("<root><item></item></root>")
      nodes = doc.xpath("//item")

      expect(described_class.first_node_text(nodes)).to eq("")
    end

    it "handles nodes with whitespace text" do
      doc = context.parse("<root><item>   </item></root>")
      nodes = doc.xpath("//item")

      expect(described_class.first_node_text(nodes)).to eq("   ")
    end
  end

  describe "edge cases" do
    it "handles Float::INFINITY in to_boolean" do
      expect(described_class.to_boolean(Float::INFINITY)).to be(true)
    end

    it "handles -Float::INFINITY in to_boolean" do
      expect(described_class.to_boolean(-Float::INFINITY)).to be(true)
    end

    it "handles scientific notation strings in to_float" do
      expect(described_class.to_float("1.5e2")).to eq(150.0)
    end

    it "handles negative numbers in to_float" do
      expect(described_class.to_float("-42.5")).to eq(-42.5)
    end

    it "handles very large numbers" do
      large_num = 10**100
      expect(described_class.to_string(large_num)).to eq(large_num.to_s)
    end
  end
end
