# frozen_string_literal: true

require "spec_helper"
require "moxml/signature"

RSpec.describe Moxml::Signature::Algorithms do
  describe "registry" do
    before { described_class.load_builtins! }

    it "registers built-in digest algorithms" do
      expect(described_class.registered?(:digest,
                                         "http://www.w3.org/2001/04/xmlenc#sha256")).to be true
      expect(described_class.registered?(:digest,
                                         "http://www.w3.org/2000/09/xmldsig#sha1")).to be true
    end

    it "registers built-in signature methods" do
      expect(described_class.registered?(:signature_method,
                                         "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")).to be true
      expect(described_class.registered?(:signature_method,
                                         "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256")).to be true
    end

    it "registers built-in canonicalization algorithms" do
      expect(described_class.registered?(:canonicalization,
                                         "http://www.w3.org/2001/10/xml-exc-c14n#")).to be true
      expect(described_class.registered?(:canonicalization,
                                         "http://www.w3.org/2001/10/xml-exc-c14n#WithComments")).to be true
    end

    it "registers built-in transform algorithms" do
      expect(described_class.registered?(:transform,
                                         "http://www.w3.org/2000/09/xmldsig#base64")).to be true
      expect(described_class.registered?(:transform,
                                         "http://www.w3.org/2000/09/xmldsig#enveloped-signature")).to be true
    end

    it "looks up a registered algorithm class" do
      klass = described_class.lookup(:digest,
                                     "http://www.w3.org/2001/04/xmlenc#sha256")
      expect(klass).to eq(Moxml::Signature::Algorithms::SHA256)
    end

    it "raises UnknownAlgorithm for unregistered URIs" do
      expect do
        described_class.lookup(:digest, "http://example.com/nonexistent")
      end.to raise_error(Moxml::Signature::UnknownAlgorithm)
    end

    it "validates category names" do
      expect do
        described_class.register(:bogus, "http://example.com", Class.new)
      end.to raise_error(ArgumentError)
    end
  end

  describe "custom algorithm registration" do
    after do
      described_class.registry[:digest]
        &.delete("http://test.example/custom-digest")
    end

    it "accepts a custom algorithm class" do
      custom = Class.new(Moxml::Signature::Algorithms::DigestBase) do
        identifier "http://test.example/custom-digest"

        def compute_digest(data)
          "x" * data.bytesize
        end
      end

      expect(described_class.lookup(:digest,
                                    "http://test.example/custom-digest")).to eq(custom)
    end
  end
end
