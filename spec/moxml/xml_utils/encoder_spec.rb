# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XmlUtils::Encoder do
  describe "#call (encoding)" do
    it "encodes XML special characters in basic mode" do
      encoder = described_class.new("<tag>content & more</tag>", :basic)
      result = encoder.call
      expect(result).to include("&lt;")
      expect(result).to include("&gt;")
      expect(result).to include("&amp;")
    end

    it "encodes quotes in full mode" do
      encoder = described_class.new('"value"', :full)
      result = encoder.call
      expect(result).to include("&quot;")
    end

    it "doesn't encode in none mode" do
      encoder = described_class.new("<tag>", :none)
      result = encoder.call
      expect(result).to eq("<tag>")
    end
  end
end
