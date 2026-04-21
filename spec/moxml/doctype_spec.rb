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

  describe "parsing" do
    %i[nokogiri oga rexml ox].each do |adapter_name|
      context "with #{adapter_name} adapter" do
        let(:ctx) { Moxml.new(adapter_name) }

        it "parses PUBLIC doctype with external and system identifiers" do
          xml = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html/>'
          doc = ctx.parse(xml)
          doctype = doc.children.find { |c| c.is_a?(described_class) }

          expect(doctype).not_to be_nil
          expect(doctype.name).to eq("html")
          expect(doctype.external_id).to eq("-//W3C//DTD XHTML 1.0 Strict//EN")
          expect(doctype.system_id).to eq("http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd")
        end

        it "parses SYSTEM doctype with system identifier only" do
          xml = '<!DOCTYPE config SYSTEM "config.dtd"><config/>'
          doc = ctx.parse(xml)
          doctype = doc.children.find { |c| c.is_a?(described_class) }

          expect(doctype).not_to be_nil
          expect(doctype.name).to eq("config")
          expect(doctype.external_id).to be_nil
          expect(doctype.system_id).to eq("config.dtd")
        end

        it "parses simple doctype without identifiers" do
          xml = "<!DOCTYPE html><html/>"
          doc = ctx.parse(xml)
          doctype = doc.children.find { |c| c.is_a?(described_class) }

          expect(doctype).not_to be_nil
          expect(doctype.name).to eq("html")
          expect(doctype.external_id).to be_nil
          expect(doctype.system_id).to be_nil
        end
      end
    end
  end
end
