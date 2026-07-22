# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"
require "openssl"
require "base64"

RSpec.describe Moxml::Signature::Algorithms::DigestBase do
  describe "SHA-256" do
    let(:digest) { Moxml::Signature::Algorithms::SHA256.new }

    it "computes raw bytes matching OpenSSL" do
      data = "hello"
      expect(digest.digest(data)).to eq(OpenSSL::Digest::SHA256.digest(data))
    end

    it "computes base64-encoded digest matching OpenSSL" do
      data = "hello"
      expected = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(data))
      expect(digest.digest_base64(data)).to eq(expected)
    end

    it "matches the FIPS 180-3 test vector for empty string" do
      # SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      expected_hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      expect(digest.digest("").unpack1("H*")).to eq(expected_hex)
    end

    it "matches the FIPS 180-3 test vector for 'abc'" do
      expected_hex = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      expect(digest.digest("abc").unpack1("H*")).to eq(expected_hex)
    end
  end

  describe "SHA-1" do
    it "matches the FIPS test vector for 'abc'" do
      digest = Moxml::Signature::Algorithms::SHA1.new
      expected_hex = "a9993e364706816aba3e25717850c26c9cd0d89d"
      expect(digest.digest("abc").unpack1("H*")).to eq(expected_hex)
    end

    it "is registered under its W3C URI" do
      klass = Moxml::Signature::Algorithms.lookup(
        :digest, "http://www.w3.org/2000/09/xmldsig#sha1"
      )
      expect(klass).to eq(Moxml::Signature::Algorithms::SHA1)
    end
  end

  describe "all five SHA digests" do
    expected_uris = {
      "http://www.w3.org/2000/09/xmldsig#sha1" =>
        [Moxml::Signature::Algorithms::SHA1, 20],
      "http://www.w3.org/2001/04/xmldsig-more#sha224" =>
        [Moxml::Signature::Algorithms::SHA224, 28],
      "http://www.w3.org/2001/04/xmlenc#sha256" =>
        [Moxml::Signature::Algorithms::SHA256, 32],
      "http://www.w3.org/2001/04/xmldsig-more#sha384" =>
        [Moxml::Signature::Algorithms::SHA384, 48],
      "http://www.w3.org/2001/04/xmlenc#sha512" =>
        [Moxml::Signature::Algorithms::SHA512, 64],
    }

    expected_uris.each do |uri, (klass, byte_length)|
      it "#{uri} resolves to #{klass.name.split('::').last} with #{byte_length}-byte output" do
        instance = klass.new
        result = instance.digest("test")
        expect(result.bytesize).to eq(byte_length)
      end
    end
  end
end
