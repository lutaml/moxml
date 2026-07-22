# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"

RSpec.describe Moxml::Signature::Algorithms::HmacSha do
  let(:secret) { "super-secret-shared-key" }
  let(:data) { "the quick brown fox" }

  describe "HMAC-SHA256" do
    let(:uri) { "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256" }
    let(:algo) { described_class.new(identifier_uri: uri) }

    it "produces a verifiable MAC" do
      mac = algo.sign(data, secret)
      expect(algo.verify(data, secret, mac)).to be true
    end

    it "rejects a tampered payload" do
      mac = algo.sign(data, secret)
      expect(algo.verify("#{data}!", secret, mac)).to be false
    end

    it "matches OpenSSL HMAC for the same inputs" do
      mac = algo.sign(data, secret)
      expected = OpenSSL::HMAC.digest("SHA256", secret, data)
      expect(mac).to eq(expected)
    end
  end

  describe "HMAC truncation" do
    let(:uri) { "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256" }

    it "truncates to the specified bit length" do
      algo = described_class.new(
        identifier_uri: uri,
        parameters: { hmac_output_length: 128 },
      )
      mac = algo.sign(data, secret)
      expect(mac.bytesize).to eq(16)
    end

    it "rejects truncation below hash_bits / 2" do
      expect do
        described_class.new(
          identifier_uri: uri,
          parameters: { hmac_output_length: 64 },
        )
      end.to raise_error(Moxml::Signature::SignatureError)
    end

    it "rejects truncation below 80 bits even for SHA-1" do
      expect do
        described_class.new(
          identifier_uri: "http://www.w3.org/2000/09/xmldsig#hmac-sha1",
          parameters: { hmac_output_length: 72 },
        )
      end.to raise_error(Moxml::Signature::SignatureError)
    end

    it "rejects truncation that is not a multiple of 8" do
      expect do
        described_class.new(
          identifier_uri: uri,
          parameters: { hmac_output_length: 130 },
        )
      end.to raise_error(Moxml::Signature::SignatureError)
    end
  end
end
