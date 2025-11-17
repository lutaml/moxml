# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Adapter do
  describe "adapter loading" do
    it "provides Nokogiri adapter" do
      expect(described_class::Nokogiri).to be_a(Class)
      expect(described_class::Nokogiri.ancestors).to include(Moxml::Adapter::Base)
    end

    it "provides Base adapter class" do
      expect(described_class::Base).to be_a(Class)
    end
  end
end
