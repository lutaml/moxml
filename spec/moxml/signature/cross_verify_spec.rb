# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

RSpec.describe "Ported reference fixtures (cross-verification)" do
  let(:ctx) { Moxml.new(:nokogiri) }
  let(:fixtures_dir) do
    File.expand_path("../../fixtures/xmldsig", __dir__)
  end

  describe "sign3-result.xml (libxmlsec1 with embedded X509Certificate)" do
    let(:xml) { File.read(File.join(fixtures_dir, "sign3-result.xml")) }
    let(:doc) { ctx.parse(xml) }

    it "auto-extracts the verification key from X509Certificate" do
      # No explicit key passed — Verifier should auto-extract from KeyInfo.
      result = Moxml::Signature.verify(context: ctx, document: doc)
      expect(result.valid?).to be true
      expect(result.results.first.signature_valid?).to be true
      expect(result.results.first.references.first.valid?).to be true
    end

    it "parses the X509Data correctly" do
      sig_elem = doc.at_xpath(
        "//ds:Signature", "ds" => "http://www.w3.org/2000/09/xmldsig#"
      )
      parsed = Moxml::Signature::Parser.new(context: ctx).parse(sig_elem)
      expect(parsed.key_info).not_to be_nil
      expect(parsed.key_info.x509_data).not_to be_nil
      expect(parsed.key_info.x509_data.certificates.size).to eq(1)

      extractor = Moxml::Signature::KeyExtractor.new
      key = extractor.extract(parsed.key_info)
      expect(key).to be_a(OpenSSL::PKey::RSA)
    end
  end

  describe "sign2-result.xml (libxmlsec1 with KeyName only)" do
    let(:xml) { File.read(File.join(fixtures_dir, "sign2-result.xml")) }
    let(:doc) { ctx.parse(xml) }
    let(:pub_key_path) { File.join(fixtures_dir, "keys", "rsa_ref.pub") }

    it "cross-verifies with the Ruby ref's RSA public key" do
      skip "public key fixture not present" unless File.exist?(pub_key_path)

      pub = OpenSSL::PKey::RSA.new(File.read(pub_key_path))
      result = Moxml::Signature.verify(context: ctx, document: doc, key: pub)
      expect(result.valid?).to be true
    end

    it "auto-resolves KeyName via the application key_map" do
      skip "public key fixture not present" unless File.exist?(pub_key_path)

      pub = OpenSSL::PKey::RSA.new(File.read(pub_key_path))
      # The fixture uses <KeyName>test</KeyName>; map it.
      result = Moxml::Signature.verify(
        context: ctx, document: doc, key_map: { "test" => pub },
      )
      expect(result.valid?).to be true
    end
  end
end
