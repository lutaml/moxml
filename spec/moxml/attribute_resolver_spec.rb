# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::AttributeResolver do
  let(:context) { Moxml.new }
  let(:doc) do
    context.parse(<<~XML)
      <root xmlns:p="http://x.org" xmlns:q="http://x.org">
        <e q:type="namespaced" type="bare"/>
      </root>
    XML
  end
  let(:element) { doc.root.children.find(&:element?) }

  describe ".resolve" do
    it "matches bare names against no-namespace attributes only" do
      expect(described_class.resolve(element, "type")&.value).to eq("bare")
    end

    it "matches prefixed names by expanded name" do
      expect(described_class.resolve(element, "p:type")&.value)
        .to eq("namespaced")
      expect(described_class.resolve(element, "q:type")&.value)
        .to eq("namespaced")
    end

    it "returns nil for undeclared prefixes and declarations" do
      expect(described_class.resolve(element, "z:type")).to be_nil
      expect(described_class.resolve(element, "xmlns:q")).to be_nil
    end
  end

  describe ".assign" do
    it "delegates xmlns declarations to the adapter" do
      described_class.assign(element, "xmlns:r", "http://r.org")
      expect(doc.to_xml).to include('xmlns:r="http://r.org"')
    end

    it "replaces the matching attribute in place" do
      described_class.assign(element, "p:type", "rewritten")
      expect(element["q:type"]).to eq("rewritten")
      expect(element.attributes.size).to eq(2)
    end

    it "stores undeclared prefixes raw until they come into scope" do
      described_class.assign(element, "z:type", "value")
      expect(element["z:type"]).to be_nil

      element.add_namespace("z", "http://z.org")
      expect(element["z:type"]).to eq("value")
    end
  end

  describe ".remove" do
    it "removes by expanded name and returns the attribute" do
      removed = described_class.remove(element, "p:type")
      expect(removed.value).to eq("namespaced")
      expect(element["q:type"]).to be_nil
      expect(element["type"]).to eq("bare")
    end

    it "returns nil when nothing matches" do
      expect(described_class.remove(element, "z:type")).to be_nil
    end
  end

  describe ".attribute_test?" do
    let(:attributes) { element.attributes }

    it "applies Namespaces 1.0 §5.2 to bare names" do
      bare = attributes.find { |a| a.value == "bare" }
      namespaced = attributes.find { |a| a.value == "namespaced" }
      expect(described_class.attribute_test?(element, bare, nil, "type"))
        .to be(true)
      expect(described_class.attribute_test?(element, namespaced, nil, "type"))
        .to be(false)
    end

    it "matches prefixed tests by URI and accepts any local for nil" do
      namespaced = attributes.find { |a| a.value == "namespaced" }
      expect(described_class.attribute_test?(element, namespaced, "p", "type"))
        .to be(true)
      expect(described_class.attribute_test?(element, namespaced, "p", nil))
        .to be(true)
      expect(described_class.attribute_test?(element, namespaced, "z", "type"))
        .to be(false)
    end

    it "treats :any as any namespace including none" do
      bare = attributes.find { |a| a.value == "bare" }
      expect(described_class.attribute_test?(element, bare, :any, "type"))
        .to be(true)
    end
  end

  describe ".attribute_test_uri?" do
    it "matches the compile-time URI regardless of document prefixes" do
      namespaced = element.attributes.find { |a| a.value == "namespaced" }
      expect(described_class.attribute_test_uri?(
               element, namespaced, "http://x.org", "type"
             )).to be(true)
      expect(described_class.attribute_test_uri?(
               element, namespaced, "http://other.org", "type"
             )).to be(false)
    end
  end
end
