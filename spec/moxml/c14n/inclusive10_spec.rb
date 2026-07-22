# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"

RSpec.describe Moxml::C14n::Inclusive10 do
  let(:ctx) { Moxml.new(:nokogiri) }
  let(:canon) { described_class.new }

  it "renders a simple element" do
    doc = ctx.parse("<root>hello</root>")
    expect(canon.canonicalize(doc.root)).to eq("<root>hello</root>")
  end

  it "attracts ancestor namespaces at the apex (the key inclusive behavior)" do
    xml = <<~XML.strip
      <outer xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar">
        <inner x="1"><foo:child>hello</foo:child></inner>
      </outer>
    XML
    doc = ctx.parse(xml)
    inner = doc.at_xpath("//*[local-name()='inner']")
    result = canon.canonicalize(inner)
    # Both inherited namespaces are rendered on <inner>, even though
    # <inner> itself does not visibly use them. This is the inclusive
    # "ancestor attraction" behavior.
    expect(result).to include('xmlns:bar="http://example.com/bar"')
    expect(result).to include('xmlns:foo="http://example.com/foo"')
  end

  it "renders each namespace declaration only once per chain" do
    xml = <<~XML.strip
      <root xmlns:a="http://example.com/a">
        <child xmlns:a="http://example.com/a"><grand/></child>
      </root>
    XML
    doc = ctx.parse(xml)
    result = canon.canonicalize(doc.root)
    expect(result.scan('xmlns:a="http://example.com/a"').count).to eq(1)
  end

  it "re-renders a namespace when re-declared with a different URI" do
    xml = <<~XML.strip
      <root xmlns:a="http://example.com/a">
        <child xmlns:a="http://example.com/other"><grand/></child>
      </root>
    XML
    doc = ctx.parse(xml)
    result = canon.canonicalize(doc.root)
    expect(result.scan("xmlns:a=").count).to eq(2)
  end

  it "renders the default namespace at apex when inherited" do
    xml = '<outer xmlns="http://example.com"><inner/></outer>'
    doc = ctx.parse(xml)
    inner = doc.at_xpath("//*[local-name()='inner']")
    result = canon.canonicalize(inner)
    expect(result).to include('xmlns="http://example.com"')
  end
end
