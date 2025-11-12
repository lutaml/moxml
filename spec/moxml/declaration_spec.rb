# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Declaration do
  let(:context) { Moxml.new }
  let(:doc) { context.create_document }

  describe "#version" do
    it "returns XML version" do
      decl = doc.create_declaration("1.0", "UTF-8")
      expect(decl.version).to eq("1.0")
    end
  end

  describe "#encoding" do
    it "returns encoding" do
      decl = doc.create_declaration("1.0", "UTF-8")
      expect(decl.encoding).to eq("UTF-8")
    end
  end

  describe "creation" do
    it "creates declaration with defaults" do
      decl = doc.create_declaration
      expect(decl).to be_a(described_class)
      expect(decl.version).to eq("1.0")
    end

    it "creates declaration with custom values" do
      decl = doc.create_declaration("1.0", "ISO-8859-1")
      expect(decl.version).to eq("1.0")
      expect(decl.encoding).to eq("ISO-8859-1")
    end
  end
end
