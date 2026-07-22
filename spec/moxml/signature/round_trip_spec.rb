# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

# End-to-end signing + verification, including tamper detection and
# wrong-key rejection. Uses real model instances and real OpenSSL keys
# per the project's "no doubles" rule.
RSpec.describe "Moxml XML Signature end-to-end round trip" do
  let(:ctx) { Moxml.new(:nokogiri) }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:document_xml) { "<doc><greeting>Hello, World!</greeting></doc>" }

  let(:common_options) do
    {
      context: ctx,
      signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
      canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
      digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
      reference_uri: "",
      transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
    }
  end

  def sign_and_attach(xml, key, **opts)
    doc = ctx.parse(xml)
    signature = Moxml::Signature.sign(document: doc, key: key, **common_options.merge(opts))
    serialized = Moxml::Signature::Serializer.new(context: ctx).serialize(signature)
    doc.root.add_child(serialized.root)
    doc
  end

  describe "RSA-SHA256 round trip" do
    it "verifies a freshly-signed document" do
      doc = sign_and_attach(document_xml, private_key)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: private_key)
      expect(result.valid?).to be true
      expect(result.signature_count).to eq(1)
    end

    it "verifies with the public key alone" do
      doc = sign_and_attach(document_xml, private_key)
      pub = OpenSSL::PKey::RSA.new(private_key.public_to_pem)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: pub)
      expect(result.valid?).to be true
    end

    it "detects payload tampering" do
      doc = sign_and_attach(document_xml, private_key)
      greeting = doc.at_xpath("//greeting")
      greeting.text = "Goodbye, World!"
      result = Moxml::Signature.verify(context: ctx, document: doc, key: private_key)
      expect(result.valid?).to be false
      # SignatureValue still matches (SignedInfo unchanged) but reference
      # digest mismatches.
      expect(result.results.first.signature_valid?).to be true
      expect(result.results.first.references.first.valid?).to be false
    end

    it "detects SignedInfo tampering" do
      doc = sign_and_attach(document_xml, private_key)
      dv = doc.at_xpath("//ds:DigestValue",
                        "ds" => "http://www.w3.org/2000/09/xmldsig#")
      dv.text = Base64.strict_encode64("x" * 32)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: private_key)
      expect(result.valid?).to be false
    end

    it "rejects an unrelated verification key" do
      doc = sign_and_attach(document_xml, private_key)
      other = OpenSSL::PKey::RSA.generate(2048)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: other)
      expect(result.valid?).to be false
      expect(result.results.first.signature_valid?).to be false
    end
  end

  describe "HMAC-SHA256 round trip" do
    let(:hmac_options) do
      common_options.merge(
        signature_method: "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
      )
    end

    it "verifies with the shared secret" do
      doc = sign_and_attach(document_xml, "shared-secret", **hmac_options)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: "shared-secret")
      expect(result.valid?).to be true
    end

    it "rejects the wrong secret" do
      doc = sign_and_attach(document_xml, "shared-secret", **hmac_options)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: "wrong-secret")
      expect(result.valid?).to be false
    end
  end

  describe "fixture key" do
    let(:pem_path) do
      File.expand_path("../../fixtures/xmldsig/keys/rsa_private.pem", __dir__)
    end
    let(:fixture_key) { OpenSSL::PKey::RSA.new(File.read(pem_path)) }

    it "loads and round-trips" do
      skip "fixture key not present" unless File.exist?(pem_path)

      doc = sign_and_attach(document_xml, fixture_key)
      result = Moxml::Signature.verify(context: ctx, document: doc, key: fixture_key)
      expect(result.valid?).to be true
    end
  end
end
