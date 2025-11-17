# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Doctype do
  let(:context) { Moxml.new }
  let(:doc) { context.create_document }

  describe "#name" do
    it "returns doctype name" do
      skip "Doctype accessor methods not yet implemented in all adapters"
      doctype = doc.create_doctype("root", nil, "test.dtd")
      expect(doctype.name).to eq("root")
    end
  end

  describe "#system_id" do
    it "returns system identifier" do
      skip "Doctype accessor methods not yet implemented in all adapters"
      doctype = doc.create_doctype("root", nil, "test.dtd")
      expect(doctype.system_id).to eq("test.dtd")
    end
  end

  describe "creation" do
    it "creates a doctype" do
      skip "Doctype accessor methods not yet implemented in all adapters"
      doctype = doc.create_doctype("html", nil, nil)
      expect(doctype).to be_a(described_class)
      expect(doctype.name).to eq("html")
    end
  end
end
