# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Moxml node caching", :performance do
  shared_examples "cached children" do |adapter_name|
    let(:ctx) { Moxml::Context.new(adapter_name) }
    let(:xml) { "<root><a/><b/><c/></root>" }
    let(:doc) { ctx.parse(xml) }
    let(:root) { doc.root }

    describe "Node#children caching" do
      it "returns the same NodeSet object on repeated calls" do
        children1 = root.children
        children2 = root.children
        expect(children1).to equal(children2)
      end

      it "returns consistent child elements across calls" do
        children1 = root.children.to_a
        children2 = root.children.to_a
        expect(children1.map(&:name)).to eq(children2.map(&:name))
      end

      it "invalidates cache when a child is added" do
        children_before = root.children
        root.add_child(ctx.parse("<d/>").root)
        children_after = root.children
        expect(children_before).not_to equal(children_after)
        expect(children_after.to_a.size).to eq(4)
      end

      it "invalidates cache when text is set" do
        children_before = root.children
        root.text = "new text"
        children_after = root.children
        expect(children_before).not_to equal(children_after)
      end
    end

    describe "Element#attributes caching" do
      let(:attr_xml) { '<root a="1" b="2"><child c="3"/></root>' }
      let(:attr_doc) { ctx.parse(attr_xml) }
      let(:attr_root) { attr_doc.root }

      it "returns the same array on repeated calls" do
        attrs1 = attr_root.attributes
        attrs2 = attr_root.attributes
        expect(attrs1).to equal(attrs2)
      end

      it "returns consistent attribute values" do
        attrs = attr_root.attributes
        expect(attrs.map { |a| [a.name, a.value] }.to_h).to eq({ "a" => "1", "b" => "2" })
      end

      it "invalidates cache when an attribute is set" do
        attrs_before = attr_root.attributes
        attr_root["c"] = "3"
        attrs_after = attr_root.attributes
        expect(attrs_before).not_to equal(attrs_after)
        expect(attrs_after.size).to eq(3)
      end

      it "invalidates cache when an attribute is removed" do
        attrs_before = attr_root.attributes
        attr_root.remove_attribute("a")
        attrs_after = attr_root.attributes
        expect(attrs_before).not_to equal(attrs_after)
        expect(attrs_after.size).to eq(1)
      end
    end

    describe "Element#namespaces caching" do
      let(:ns_xml) { '<root xmlns:a="http://a.com" xmlns:b="http://b.com"><a:child/></root>' }
      let(:ns_doc) { ctx.parse(ns_xml) }
      let(:ns_root) { ns_doc.root }

      it "returns the same array on repeated calls" do
        nss1 = ns_root.namespaces
        nss2 = ns_root.namespaces
        expect(nss1).to equal(nss2)
      end

      it "invalidates cache when a namespace is added" do
        nss_before = ns_root.namespaces
        ns_root.add_namespace("c", "http://c.com")
        nss_after = ns_root.namespaces
        expect(nss_before).not_to equal(nss_after)
        expect(nss_after.size).to eq(3)
      end
    end
  end

  describe "Nokogiri adapter" do
    it_behaves_like "cached children", :nokogiri
  end

  describe "Ox adapter" do
    it_behaves_like "cached children", :ox
  end
end
