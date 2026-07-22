# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

RSpec.describe Moxml::Signature::KeyExtractor do
  let(:extractor) { described_class.new }

  describe "RSAKeyValue" do
    let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }

    it "reconstructs a public RSA key from Modulus and Exponent" do
      require "base64"
      n_b64 = Base64.strict_encode64(rsa_key.n.to_s(2))
      e_b64 = Base64.strict_encode64(rsa_key.e.to_s(2))
      key_value = Moxml::Signature::Model::KeyValue.new(
        rsa_key_value: Moxml::Signature::Model::Key::RSAKeyValue.new(
          modulus: n_b64,
          exponent: e_b64,
        ),
      )
      key_info = Moxml::Signature::Model::KeyInfo.new(key_value: key_value)
      extracted = extractor.extract(key_info)
      expect(extracted).to be_a(OpenSSL::PKey::RSA)
      expect(extracted.n).to eq(rsa_key.n)
      expect(extracted.e).to eq(rsa_key.e)
    end
  end

  describe "X509Certificate" do
    let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:cert) do
      # Generate a self-signed cert so we can round-trip the DER.
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = OpenSSL::X509::Name.parse("/CN=test")
      cert.issuer = cert.subject
      cert.public_key = rsa_key
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600
      cert.sign(rsa_key, OpenSSL::Digest.new("SHA256"))
      cert
    end

    it "extracts the public key from the certificate" do
      require "base64"
      key_info = Moxml::Signature::Model::KeyInfo.new(
        x509_data: Moxml::Signature::Model::Key::X509Data.new(
          # X509Certificate is stored as base64-encoded DER (spec §4.5.4).
          certificates: [Base64.strict_encode64(cert.to_der)],
        ),
      )
      extracted = extractor.extract(key_info)
      expect(extracted).to be_a(OpenSSL::PKey::RSA)
      expect(extracted.n).to eq(rsa_key.n)
    end
  end

  describe "KeyName" do
    it "looks up the key in the application-supplied map" do
      key = OpenSSL::PKey::RSA.generate(2048)
      extractor_with_map = described_class.new(key_map: { "my-key" => key })
      key_info = Moxml::Signature::Model::KeyInfo.new(key_name: "my-key")
      expect(extractor_with_map.extract(key_info)).to equal(key)
    end

    it "returns nil for an unknown key name" do
      key_info = Moxml::Signature::Model::KeyInfo.new(key_name: "unknown")
      expect(extractor.extract(key_info)).to be_nil
    end
  end

  describe "ECKeyValue" do
    it "reconstructs a P-256 public EC key" do
      ec = OpenSSL::PKey::EC.generate("prime256v1")
      # Spec §4.5.2.3: PublicKey contains the uncompressed-point form
      # 0x04 || x || y, base64-encoded.
      point_octets = ec.public_key.to_octet_string(:uncompressed)
      ec_pub_b64 = Base64.strict_encode64(point_octets)

      key_info = Moxml::Signature::Model::KeyInfo.new(
        key_value: Moxml::Signature::Model::KeyValue.new(
          ec_key_value: Moxml::Signature::Model::Key::ECKeyValue.new(
            named_curve_uri: "urn:oid:1.2.840.10045.3.1.7",
            public_key: ec_pub_b64,
          ),
        ),
      )
      extracted = extractor.extract(key_info)
      expect(extracted).to be_a(OpenSSL::PKey::EC)
      expect(extracted.public_key).to eq(ec.public_key)
    end
  end
end
