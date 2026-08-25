# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end

# Programmatic document construction relies on the C API added for the
# Moxml integration (leptris_document_create / leptris_document_set_root,
# exposed as Leptris::XML::Document.create / #root=). Released leptris
# 1.1.x does not ship it yet; skip instead of failing until the binding
# release catches up.
unless Leptris::XML::Document.respond_to?(:create)
  # String form: the adapter constant is not loaded in this branch —
  # resolving it would raise NameError before the skip applies.
  RSpec.describe "Moxml::Adapter::Leptris" do
    it "waits for a leptris release with programmatic document construction" do
      skip "requires leptris with Leptris::XML::Document.create (unreleased C API)"
    end
  end

  return
end

require "moxml/adapter/leptris"

RSpec.describe Moxml::Adapter::Leptris do
  around do |example|
    Moxml.with_config(:leptris, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "native xpath dispatch" do
    let(:ctx) { Moxml.new(:leptris) }
    let(:doc) do
      ctx.parse(<<~XML)
        <root xmlns:p="http://x.org">
          <item id="1" p:kind="a">alpha</item>
          <item id="2">beta</item>
        </root>
      XML
    end

    it "evaluates document-context queries on the native engine" do
      expect(doc.xpath("//item[@id='2']").map(&:text)).to eq(["beta"])
      expect(doc.xpath("count(//item)")).to eq(2.0)
      expect(doc.xpath("//item[@p:kind='a']").map { |n| n["id"] }).to eq(["1"])
    end

    it "falls back to the Ruby engine for attribute-node results" do
      attrs = doc.xpath("//item/@id")
      expect(attrs.map(&:name)).to eq(%w[id id])
      expect(attrs.map(&:value)).to eq(%w[1 2])
    end

    it "falls back to the Ruby engine for element-context queries" do
      expect(doc.root.xpath(".//item").size).to eq(2)
    end

    it "falls back to the Ruby engine for the xmlns: reserved prefix" do
      expect(doc.xpath("//xmlns:item").size).to eq(0)
      prefixed = ctx.parse('<r xmlns="http://d.org"><item/></r>')
      expect(prefixed.xpath("//xmlns:item").size).to eq(1)
    end

    it "raises Moxml::XPathError for invalid expressions" do
      expect { doc.xpath("//item[") }.to raise_error(Moxml::XPathError)
    end
  end
end
