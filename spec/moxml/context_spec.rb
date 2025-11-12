# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Context do
  let(:context) { described_class.new }

  describe "#parse" do
    it "parses XML string" do
      doc = context.parse("<root><child/></root>")
      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("root")
    end
  end

  describe "#config" do
    it "has a configuration" do
      expect(context.config).to be_a(Moxml::Config)
    end
  end

  describe "adapter access" do
    it "provides adapter through config" do
      expect(context.config.adapter).to be_a(Class)
      expect(context.config.adapter.ancestors).to include(Moxml::Adapter::Base)
    end
  end
end
