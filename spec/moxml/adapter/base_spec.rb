# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Adapter::Base do
  describe ".name" do
    it "returns adapter name" do
      expect(described_class.name).to include("Base")
    end
  end

  describe "interface methods" do
    it "defines parse method" do
      expect(described_class).to respond_to(:parse)
    end

    it "defines create_document method" do
      expect(described_class).to respond_to(:create_document)
    end

    it "defines serialize method" do
      # Base class doesn't implement serialize - each adapter does
      # This is tested in the individual adapter specs
      skip "Serialize is adapter-specific, not in Base"
    end
  end
end
