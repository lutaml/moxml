# frozen_string_literal: true

# Processing model §Access semantics (normative): pinned here.

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

    # Namespaces 1.0 §5.2: the default namespace never applies to
    # attributes. Engines that resolve unprefixed attributes against
    # the default namespace must answer nil for it, or bare-name reads
    # miss on every element under a default namespace.
    it "never treats bare attributes as default-namespace members" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
        d = Moxml.new(adapter_name).parse(%(<r xmlns="urn:a"><e id="1"/></r>))
        e = d.root.children.find(&:element?)
        expect(e["id"]).to eq("1"), "#{adapter_name}: bare read"
        expect(e.attribute("id")&.value).to eq("1"),
                                            "#{adapter_name}: resolver"
        expect(e.attribute("id")&.namespace).to be_nil,
                                                "#{adapter_name}: attribute namespace"
      end
    end

    it "keeps bare reads on programmatically built default-namespaced trees" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
        ctx = Moxml.new(adapter_name)
        d = ctx.create_document
        root = d.create_element("root")
        root.add_namespace(nil, "urn:a")
        d.add_child(root)
        e = d.create_element("item")
        e["id"] = "123"
        root.add_child(e)

        expect(e["id"]).to eq("123"), "#{adapter_name}: bare read"
        expect(d.xpath('//xmlns:item[@id="123"]').to_a.size).to eq(1),
                                                                "#{adapter_name}: xmlns predicate"
      end
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

  describe ".resolve_value capability dispatch (issue #242)" do
    it "answers prefixed values through the adapter capability, not class identity" do
      doc = Moxml.new(:nokogiri).parse(
        '<w:f xmlns:w="urn:w"><w:n w:val="Arial"/></w:f>',
      )
      node = doc.root.children.first

      expect(Moxml::Adapter::Base.expanded_attr_reads?).to be(false)
      expect(Moxml::Adapter::Nokogiri.expanded_attr_reads?).to be(false)
      expect(node["w:val"]).to eq("Arial")
    end

    it "keeps native c14n delegation behind the adapter protocol" do
      expect(Moxml::Adapter::Base.native_inclusive10(nil)).to be_nil
      expect(Moxml::Adapter::Nokogiri.native_inclusive10(nil)).to be_nil
    end
  end
end
