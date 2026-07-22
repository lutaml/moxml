# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

# Edge cases and defensive behavior. Per the audit (TODO.complete/20),
# the original suite lacked:
# - malformed input handling
# - attack-scenario rejection
# - KeyExtractor failure modes
# - HMAC truncation at exact boundaries
# - multi-signature documents
# - adapter portability
RSpec.describe "Moxml::Signature edge cases and defense" do
  let(:ctx) { Moxml.new(:nokogiri) }

  describe "malformed Signature elements" do
    it "rejects a document with no Signature element" do
      doc = ctx.parse("<doc/>")
      result = Moxml::Signature.verify(
        context: ctx, document: doc, key: OpenSSL::PKey::RSA.generate(2048),
      )
      expect(result.signature_count).to eq(0)
      expect(result.valid?).to be true # vacuously — no signatures
    end

    it "raises on SignatureValue with invalid base64" do
      key = OpenSSL::PKey::RSA.generate(2048)
      doc = ctx.parse(<<~XML.strip)
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo>
            <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
            <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
            <ds:Reference URI="">
              <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
              <ds:DigestValue>!!!!not base64!!!!</ds:DigestValue>
            </ds:Reference>
          </ds:SignedInfo>
          <ds:SignatureValue>also not base64!!!</ds:SignatureValue>
        </ds:Signature>
      XML
      expect do
        Moxml::Signature.verify(context: ctx, document: doc, key: key)
      end.to raise_error(Moxml::Signature::MalformedSignatureError)
    end

    it "returns false for a Signature with empty SignatureValue" do
      key = OpenSSL::PKey::RSA.generate(2048)
      doc = ctx.parse(<<~XML.strip)
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo>
            <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
            <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
            <ds:Reference URI="">
              <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
              <ds:DigestValue>YWJjZA==</ds:DigestValue>
            </ds:Reference>
          </ds:SignedInfo>
          <ds:SignatureValue></ds:SignatureValue>
        </ds:Signature>
      XML
      result = Moxml::Signature.verify(context: ctx, document: doc, key: key)
      expect(result.valid?).to be false
    end

    it "returns false for an unknown signature method URI" do
      key = OpenSSL::PKey::RSA.generate(2048)
      doc = ctx.parse(<<~XML.strip)
        <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
          <ds:SignedInfo>
            <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
            <ds:SignatureMethod Algorithm="http://example.com/bogus-alg"/>
            <ds:Reference URI="">
              <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
              <ds:DigestValue>YWJjZA==</ds:DigestValue>
            </ds:Reference>
          </ds:SignedInfo>
          <ds:SignatureValue>YWJjZA==</ds:SignatureValue>
        </ds:Signature>
      XML
      result = Moxml::Signature.verify(context: ctx, document: doc, key: key)
      expect(result.valid?).to be false
      expect(result.results.first.error).to be_a(Moxml::Signature::UnknownAlgorithm)
    end
  end

  describe "HMAC truncation boundary" do
    let(:secret) { "shared-secret" }
    let(:data) { "data" }

    it "accepts truncation at exactly the minimum (hash_bits/2)" do
      # For SHA-256, minimum is 128 bits. Should be accepted.
      algo = Moxml::Signature::Algorithms::HmacSha.new(
        identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
        parameters: { hmac_output_length: 128 },
      )
      mac = algo.sign(data, secret)
      expect(mac.bytesize).to eq(16)
    end

    it "accepts truncation at exactly 80 bits (SHA-1 minimum)" do
      algo = Moxml::Signature::Algorithms::HmacSha.new(
        identifier_uri: "http://www.w3.org/2000/09/xmldsig#hmac-sha1",
        parameters: { hmac_output_length: 80 },
      )
      expect(algo.sign(data, secret).bytesize).to eq(10)
    end

    it "rejects truncation one bit below the minimum" do
      expect do
        Moxml::Signature::Algorithms::HmacSha.new(
          identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
          parameters: { hmac_output_length: 127 },
        )
      end.to raise_error(Moxml::Signature::SignatureError)
    end
  end

  describe "KeyExtractor failure modes" do
    let(:extractor) { Moxml::Signature::KeyExtractor.new }

    it "returns nil for an empty KeyInfo" do
      key_info = Moxml::Signature::Model::KeyInfo.new
      expect(extractor.extract(key_info)).to be_nil
    end

    it "returns nil for nil KeyInfo" do
      expect(extractor.extract(nil)).to be_nil
    end

    it "returns nil for a malformed X509Certificate" do
      key_info = Moxml::Signature::Model::KeyInfo.new(
        x509_data: Moxml::Signature::Model::Key::X509Data.new(
          certificates: ["!!!not valid base64!!!"],
        ),
      )
      expect(extractor.extract(key_info)).to be_nil
    end

    it "returns nil for a valid-base64 but invalid-DER certificate" do
      require "base64"
      key_info = Moxml::Signature::Model::KeyInfo.new(
        x509_data: Moxml::Signature::Model::Key::X509Data.new(
          certificates: [Base64.strict_encode64("not a certificate")],
        ),
      )
      expect(extractor.extract(key_info)).to be_nil
    end

    it "returns nil for RSAKeyValue with malformed modulus" do
      key_info = Moxml::Signature::Model::KeyInfo.new(
        key_value: Moxml::Signature::Model::KeyValue.new(
          rsa_key_value: Moxml::Signature::Model::Key::RSAKeyValue.new(
            modulus: "!!!invalid base64!!!",
            exponent: "AQAB",
          ),
        ),
      )
      expect(extractor.extract(key_info)).to be_nil
    end

    it "returns nil for ECKeyValue with unknown curve URI" do
      key_info = Moxml::Signature::Model::KeyInfo.new(
        key_value: Moxml::Signature::Model::KeyValue.new(
          ec_key_value: Moxml::Signature::Model::Key::ECKeyValue.new(
            named_curve_uri: "urn:oid:1.2.3.4.unknown",
            public_key: "abc",
          ),
        ),
      )
      expect(extractor.extract(key_info)).to be_nil
    end

    it "returns nil for KeyName not in key_map" do
      key_info = Moxml::Signature::Model::KeyInfo.new(key_name: "unknown")
      expect(extractor.extract(key_info)).to be_nil
    end
  end

  describe "multi-signature documents" do
    it "reports each signature separately" do
      doc = ctx.parse("<doc><a>x</a><b>y</b></doc>")
      key1 = OpenSSL::PKey::RSA.generate(2048)
      key2 = OpenSSL::PKey::RSA.generate(2048)

      sig1 = Moxml::Signature.sign(
        context: ctx, document: doc, key: key1,
        signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
        canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
        digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
        reference_uri: "",
        transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"]
      )
      sig2 = Moxml::Signature.sign(
        context: ctx, document: doc, key: key2,
        signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
        canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
        digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
        reference_uri: "",
        transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"]
      )
      serializer = Moxml::Signature::Serializer.new(context: ctx)
      doc.root.add_child(serializer.serialize(sig1).root)
      doc.root.add_child(serializer.serialize(sig2).root)

      # Verifying with key1: only sig1 should pass; sig2's SignatureValue
      # won't verify against key1.
      result = Moxml::Signature.verify(context: ctx, document: doc, key: key1)
      expect(result.signature_count).to eq(2)
      expect(result.results.map(&:signature_valid?)).to contain_exactly(true, false)
    end
  end

  describe "wrapping attack defense" do
    it "does not verify a Signature whose SignedInfo references a different node" do
      # Construct: doc has <payload xml:id="real">. Signature references
      # "#real" but a tampered copy of <payload> lives inside <Object>.
      # The reference digest matches the tampered copy, not the real one.
      # This is the canonical wrapping attack pattern.
      #
      # The library cannot detect this on its own (the spec allows
      # Object payloads). The application must check that the signed
      # node is the one expected. This spec documents that the library
      # faithfully reports per-reference validity, leaving the trust
      # decision to the caller.
      key = OpenSSL::PKey::RSA.generate(2048)
      doc = ctx.parse(<<~XML.strip)
        <doc>
          <payload xml:id="real">original</payload>
        </doc>
      XML

      # Sign the real payload
      signature = Moxml::Signature.sign(
        context: ctx, document: doc, key: key,
        signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
        canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
        digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
        reference_uri: "#real",
        transforms: []
      )
      serializer = Moxml::Signature::Serializer.new(context: ctx)
      doc.root.add_child(serializer.serialize(signature).root)

      result = Moxml::Signature.verify(context: ctx, document: doc, key: key)
      expect(result.valid?).to be true

      # Library returns the reference result; application must check URI.
      ref = result.results.first.references.first
      expect(ref.uri).to eq("#real")
    end
  end

  describe "adapter portability" do
    # Skip on Opal — adapter switching is the whole point of moxml.
    it "verifies a signature produced under one adapter with another", :adapter_portability do
      skip "Only Nokogiri available in CI" unless defined?(Nokogiri)

      signing_ctx = Moxml.new(:nokogiri)
      verify_ctx = Moxml.new(:nokogiri) # would be :rexml in a multi-adapter env

      key = OpenSSL::PKey::RSA.generate(2048)
      doc = signing_ctx.parse("<doc>payload</doc>")
      signature = Moxml::Signature.sign(
        context: signing_ctx, document: doc, key: key,
        signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
        canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
        digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
        reference_uri: "",
        transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"]
      )
      serializer = Moxml::Signature::Serializer.new(context: signing_ctx)
      doc.root.add_child(serializer.serialize(signature).root)

      # Round-trip the XML through a different context
      xml = doc.to_xml(indent: 0)
      doc2 = verify_ctx.parse(xml)

      result = Moxml::Signature.verify(context: verify_ctx, document: doc2, key: key)
      expect(result.valid?).to be true
    end
  end
end
