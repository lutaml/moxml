# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"

RSpec.describe Moxml::Signature::Algorithms::XPathFilterTransform do
  let(:ctx) { Moxml.new(:nokogiri) }

  it "removes signature subtrees via not(ancestor-or-self::dsig:Signature)" do
    xml = <<~XML.strip
      <root xmlns:ds="#{Moxml::Signature::DSIG_NS}">
        <payload>kept</payload>
        <ds:Signature><ds:SignedInfo>dropped</ds:SignedInfo></ds:Signature>
      </root>
    XML
    doc = ctx.parse(xml)
    transform = described_class.new(
      parameters: { xpaths: ["not(ancestor-or-self::ds:Signature)"] },
      context: ctx,
    )
    result = transform.transform(doc.root)

    # All nodes except the Signature and its descendants should be included.
    names = result.filter_map do |n|
      n.name
    rescue StandardError
      nil
    end
    expect(names).to include("root", "payload")
    expect(names).not_to include("Signature", "SignedInfo")
  end

  it "raises TransformError without an XPath parameter" do
    doc = ctx.parse("<root/>")
    transform = described_class.new(parameters: {}, context: ctx)
    expect do
      transform.transform(doc.root)
    end.to raise_error(Moxml::Signature::TransformError)
  end

  it "raises TransformError on octet-stream input" do
    transform = described_class.new(
      parameters: { xpaths: ["not(ancestor-or-self::ds:Signature)"] },
      context: ctx,
    )
    expect do
      transform.transform("plain octets")
    end.to raise_error(Moxml::Signature::TransformError)
  end
end
