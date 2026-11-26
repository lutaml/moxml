# frozen_string_literal: true

require "spec_helper"

# lutaml/moxml#582 — the ea gem's Nokogiri→Moxml migration findings:
# the xpath-result attribute crash, the namespaced-attribute surface,
# and Builder construction from a document wrapper.
RSpec.describe "leptris ea-migration findings (#582)" do
  let(:ctx) { Moxml.new(:leptris) }

  describe "bug 1: xpath-result attribute to_s" do
    it "renders an attribute returned by at_xpath without crashing" do
      doc = ctx.parse('<r><a id="X"/></r>')
      attr = doc.at_xpath("//a/@id")

      expect(attr.to_s).to eq('id="X"')
    end

    it "renders a prefixed xpath-result attribute with its prefix" do
      doc = ctx.parse('<r xmlns:x="urn:x"><a x:id="Y"/></r>')
      attr = doc.at_xpath("//a/@x:id")

      expect(attr.to_s).to eq('x:id="Y"')
    end
  end

  describe "bug 2: namespaced attribute surface" do
    it "answers string bracket access with the named attribute" do
      doc = ctx.parse('<a id="1" xmi:id="X1" xmi:idref="R9"/>')

      expect(doc.root.attributes["xmi:idref"].value).to eq("R9")
      expect(doc.root.attributes["id"].value).to eq("1")
    end

    it "answers string bracket access on both adapter lanes identically" do
      %i[leptris nokogiri].each do |engine|
        doc = Moxml.new(engine).parse('<a id="1" xmi:id="X1" xmi:idref="R9"/>')

        expect(doc.root.attributes["xmi:idref"].value).to eq("R9")
      end
    end
  end

  describe "gap 5: namespace data at node level" do
    it "answers the Nokogiri href idiom on the leptris lane" do
      doc = ctx.parse('<r xmlns:x="urn:x"><a x:id="Y"/></r>')
      child = doc.root.children.first

      expect(child.namespace&.href).to be_nil # <a> is unprefixed
      expect(child.attribute("x:id").namespace&.href).to eq("urn:x")
    end
  end

  describe "bug 3: Builder from a document wrapper" do
    it "builds into a passed document wrapper" do
      doc = ctx.create_document
      builder = Moxml::Builder.new(doc)
      builder.build do
        element("root") do
          element("child")
        end
      end
      result = doc.to_xml

      expect(result).to include("<root")
      expect(result).to include("child")
      expect(doc.root.name).to eq("root")
      expect(doc.root.children.first.name).to eq("child")
    end

    it "keeps the context-first construction path working" do
      builder = Moxml::Builder.new(ctx)
      doc = builder.build { element("solo") }

      expect(doc.root.name).to eq("solo")
    end
  end
end
