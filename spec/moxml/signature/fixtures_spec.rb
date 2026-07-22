# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

# Parses fixtures produced by the nokogiri-xmlsec-instructure reference
# implementation (which wraps libxmlsec1). The fixtures are real-world
# XML signatures; verifying them byte-for-byte requires byte-exact
# canonicalization (see TODO.complete/05-c14n-engine.md — inclusive C14N
# 1.0/1.1 are stubs). These specs assert the parser handles the wire
# format correctly.
RSpec.describe "Ported reference fixtures" do
  let(:ctx) { Moxml.new(:nokogiri) }
  let(:fixtures_dir) do
    File.expand_path("../../fixtures/xmldsig", __dir__)
  end

  describe "sign2-result.xml (libxmlsec1 enveloped RSA-SHA256)" do
    let(:xml) { File.read(File.join(fixtures_dir, "sign2-result.xml")) }
    let(:doc) { ctx.parse(xml) }
    let(:signature_element) do
      doc.at_xpath("//ds:Signature", "ds" => "http://www.w3.org/2000/09/xmldsig#") ||
        doc.at_xpath("//*[local-name()='Signature']")
    end

    it "is parseable into a model" do
      parsed = Moxml::Signature::Parser.new(context: ctx).parse(signature_element)
      expect(parsed.signed_info).not_to be_nil
      expect(parsed.signed_info.canonicalization_method.algorithm)
        .to eq("http://www.w3.org/2001/10/xml-exc-c14n#")
      expect(parsed.signed_info.signature_method.algorithm)
        .to eq("http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")
      expect(parsed.signed_info.references.length).to eq(1)

      ref = parsed.signed_info.references.first
      expect(ref.digest_method.algorithm)
        .to eq("http://www.w3.org/2001/04/xmlenc#sha256")
      expect(ref.digest_value).to eq("Gx8CGUsbi2qvBLd15VCmwELbDMND8F4vY3jPOc7/FJ0=")
      # Reference uses 1024-bit RSA (libxmlsec1 test key) → 128-byte signature.
      expect(parsed.signature_value.value.bytesize).to eq(128)
    end

    it "decodes SignatureValue despite embedded newlines (libxmlsec1 wraps long base64)" do
      parsed = Moxml::Signature::Parser.new(context: ctx).parse(signature_element)
      expect(parsed.signature_value.value.bytesize).to eq(128)
    end

    it "exposes the transforms chain" do
      parsed = Moxml::Signature::Parser.new(context: ctx).parse(signature_element)
      transforms = parsed.signed_info.references.first.transforms
      expect(transforms.size).to eq(2)
      expect(transforms.transforms.map(&:algorithm)).to eq([
                                                             "http://www.w3.org/2000/09/xmldsig#enveloped-signature",
                                                             "http://www.w3.org/2001/10/xml-exc-c14n#",
                                                           ])
    end

    it "cross-verifies with the Ruby ref's RSA public key" do
      pub_pem = File.read(File.join(fixtures_dir, "keys", "rsa_ref.pub"))
      pub = OpenSSL::PKey::RSA.new(pub_pem)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: pub)
      expect(result.valid?).to be true
      expect(result.results.first.signature_valid?).to be true
      expect(result.results.first.references.first.valid?).to be true
    end
  end

  describe "sign2-doc.xml (the unsigned payload)" do
    let(:xml) { File.read(File.join(fixtures_dir, "sign2-doc.xml")) }

    it "is the expected enveloped payload" do
      doc = ctx.parse(xml)
      expect(doc.root.name).to eq("Envelope")
      # Data is in the default urn:envelope namespace.
      data = doc.at_xpath("//*[local-name()='Data']")
      expect(data.text.strip).to eq("Hello, World!")
    end
  end
end
