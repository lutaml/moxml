# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

RSpec.describe Moxml::Signature::Algorithms::DsaSha do
  let(:key) { OpenSSL::PKey::DSA.generate(2048) }
  let(:data) { "the quick brown fox jumps over the lazy dog" }

  it "round-trips DSA-SHA1" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2000/09/xmldsig#dsa-sha1",
    )
    sig = algo.sign(data, key)
    # DSA q for 2048-bit DSA is 256 bits → 32-byte halves → 64-byte raw sig.
    expect(sig.bytesize).to eq(64)
    expect(algo.verify(data, key, sig)).to be true
  end

  it "round-trips DSA-SHA256" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2009/xmldsig11#dsa-sha256",
    )
    sig = algo.sign(data, key)
    expect(sig.bytesize).to eq(64)
    expect(algo.verify(data, key, sig)).to be true
  end

  it "rejects tampered payload" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2009/xmldsig11#dsa-sha256",
    )
    sig = algo.sign(data, key)
    expect(algo.verify("#{data}!", key, sig)).to be false
  end

  it "rejects non-DSA keys" do
    algo = described_class.new(
      identifier_uri: "http://www.w3.org/2009/xmldsig11#dsa-sha256",
    )
    expect do
      algo.sign(data, OpenSSL::PKey::RSA.generate(2048))
    end.to raise_error(Moxml::Signature::SignatureKeyError)
  end
end
