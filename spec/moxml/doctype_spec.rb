# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Doctype do
  let(:context) { Moxml.new }
  let(:doc) { context.create_document }

  describe "#name" do
    it "returns doctype name" do
      doctype = doc.create_doctype("root", nil, "test.dtd")
      expect(doctype.name).to eq("root")
    end
  end

  describe "#system_id" do
    it "returns system identifier" do
      doctype = doc.create_doctype("root", nil, "test.dtd")
      expect(doctype.system_id).to eq("test.dtd")
    end
  end

  describe "#external_id" do
    it "returns external identifier when present" do
      doctype = doc.create_doctype("html", "-//W3C//DTD HTML 4.01//EN", "http://www.w3.org/TR/html4/strict.dtd")
      expect(doctype.external_id).to eq("-//W3C//DTD HTML 4.01//EN")
    end

    it "returns nil when not present" do
      doctype = doc.create_doctype("root", nil, "test.dtd")
      expect(doctype.external_id).to be_nil
    end
  end

  describe "#identifier" do
    it "returns the doctype name" do
      doctype = doc.create_doctype("html", nil, nil)
      expect(doctype.identifier).to eq("html")
    end
  end

  describe "creation" do
    it "creates a doctype" do
      doctype = doc.create_doctype("html", nil, nil)
      expect(doctype).to be_a(described_class)
      expect(doctype.name).to eq("html")
    end
  end
end
