# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"

RSpec.describe Moxml::Signature::Model do
  describe Moxml::Signature::Model::Signature do
    it "stores its components" do
      si = Moxml::Signature::Model::SignedInfo.new
      sv = Moxml::Signature::Model::SignatureValue.new(value: "abc")
      sig = described_class.new(id: "S1", signed_info: si, signature_value: sv)
      expect(sig.id).to eq("S1")
      expect(sig.signed_info).to equal(si)
      expect(sig.signature_value).to equal(sv)
      expect(sig.objects).to eq([])
    end
  end

  describe Moxml::Signature::Model::Reference do
    it "accepts uri, transforms, and digest method" do
      t = Moxml::Signature::Model::Transforms.new(
        transforms: [Moxml::Signature::Model::Transform.new(
          algorithm: "http://www.w3.org/2000/09/xmldsig#enveloped-signature",
        )],
      )
      dm = Moxml::Signature::Model::DigestMethod.new(
        algorithm: "http://www.w3.org/2001/04/xmlenc#sha256",
      )
      ref = described_class.new(uri: "", transforms: t, digest_method: dm,
                                digest_value: "abc=")
      expect(ref.uri).to eq("")
      expect(ref.transforms.transforms.size).to eq(1)
      expect(ref.digest_method.algorithm).to eq(
        "http://www.w3.org/2001/04/xmlenc#sha256",
      )
      expect(ref.digest_value).to eq("abc=")
    end
  end

  describe Moxml::Signature::Model::Transforms do
    it "is empty by default" do
      expect(described_class.new).to be_empty
    end

    it "appends transforms with <<" do
      transforms = described_class.new
      t = Moxml::Signature::Model::Transform.new(
        algorithm: "http://www.w3.org/2000/09/xmldsig#base64",
      )
      transforms << t
      expect(transforms.size).to eq(1)
    end
  end
end
