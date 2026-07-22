# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

RSpec.describe Moxml::Signature::Algorithms::RsaPkcs1Sha do
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:data) { "the quick brown fox jumps over the lazy dog" }

  describe "RSA-SHA256" do
    let(:uri) { "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" }
    let(:algo) { described_class.new(identifier_uri: uri) }

    it "produces a verifiable signature" do
      signature = algo.sign(data, key)
      expect(algo.verify(data, key, signature)).to be true
    end

    it "rejects a tampered payload" do
      signature = algo.sign(data, key)
      expect(algo.verify("#{data}!", key, signature)).to be false
    end

    it "rejects verification with a different key" do
      other_key = OpenSSL::PKey::RSA.generate(2048)
      signature = algo.sign(data, key)
      expect(algo.verify(data, other_key, signature)).to be false
    end
  end

  describe "RSA-SHA1 / SHA224 / SHA384 / SHA512" do
    %w[
      http://www.w3.org/2000/09/xmldsig#rsa-sha1
      http://www.w3.org/2001/04/xmldsig-more#rsa-sha224
      http://www.w3.org/2001/04/xmldsig-more#rsa-sha384
      http://www.w3.org/2001/04/xmldsig-more#rsa-sha512
    ].each do |uri|
      it "#{uri} round-trips sign/verify" do
        algo = described_class.new(identifier_uri: uri)
        sig = algo.sign(data, key)
        expect(algo.verify(data, key, sig)).to be true
      end
    end
  end

  it "rejects a non-RSA key" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
    )
    expect do
      algo.sign(data, "not-a-key")
    end.to raise_error(Moxml::Signature::SignatureKeyError)
  end
end
