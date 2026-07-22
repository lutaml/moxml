# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

RSpec.describe Moxml::Signature::Algorithms::EcdsaSha do
  let(:key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:data) { "the quick brown fox jumps over the lazy dog" }

  %w[
    http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha1
    http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha224
    http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256
    http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384
    http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512
  ].each do |uri|
    it "#{uri} round-trips sign/verify on P-256" do
      algo = described_class.new(identifier_uri: uri)
      sig = algo.sign(data, key)
      # P-256: 32-byte r ‖ 32-byte s = 64 bytes
      expect(sig.bytesize).to eq(64)
      expect(algo.verify(data, key, sig)).to be true
    end
  end

  it "rejects tampered payload" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256",
    )
    sig = algo.sign(data, key)
    expect(algo.verify("#{data}!", key, sig)).to be false
  end

  it "rejects verification with a different key" do
    other = OpenSSL::PKey::EC.generate("prime256v1")
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256",
    )
    sig = algo.sign(data, key)
    expect(algo.verify(data, other, sig)).to be false
  end

  it "supports P-384 with 48-byte coordinates" do
    p384 = OpenSSL::PKey::EC.generate("secp384r1")
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384",
    )
    sig = algo.sign(data, p384)
    expect(sig.bytesize).to eq(96)
    expect(algo.verify(data, p384, sig)).to be true
  end

  it "supports P-521 with 66-byte coordinates" do
    p521 = OpenSSL::PKey::EC.generate("secp521r1")
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512",
    )
    sig = algo.sign(data, p521)
    expect(sig.bytesize).to eq(132)
    expect(algo.verify(data, p521, sig)).to be true
  end

  it "rejects non-EC keys" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256",
    )
    expect do
      algo.sign(data, OpenSSL::PKey::RSA.generate(2048))
    end.to raise_error(Moxml::Signature::SignatureKeyError)
  end
end
