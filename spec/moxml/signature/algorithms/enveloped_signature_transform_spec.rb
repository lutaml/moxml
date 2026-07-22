# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"

RSpec.describe Moxml::Signature::Algorithms::EnvelopedSignatureTransform do
  let(:ctx) { Moxml.new(:nokogiri) }

  it "is a no-op when signature_element is nil (signing case)" do
    doc = ctx.parse("<root><child/></root>")
    root = doc.root
    transform = described_class.new(context: ctx, signature_element: nil)
    expect(transform.transform(root)).to equal(root)
  end

  it "removes the containing signature from a copy (verification case)" do
    xml = <<~XML.strip
      <root>
        <payload>important</payload>
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo/>
        </ds:Signature>
      </root>
    XML
    doc = ctx.parse(xml)
    sig_elem = doc.at_xpath("//ds:Signature",
                            "ds" => "http://www.w3.org/2000/09/xmldsig#")

    transform = described_class.new(context: ctx, signature_element: sig_elem)
    result = transform.transform(doc.root)

    expect(doc.at_xpath("//ds:Signature",
                        "ds" => "http://www.w3.org/2000/09/xmldsig#")).not_to be_nil

    c14n = Moxml::Signature::C14n::Exclusive.new
    canonical = c14n.canonicalize(result)
    expect(canonical).not_to include("Signature")
    expect(canonical).to include("important")
  end
end
