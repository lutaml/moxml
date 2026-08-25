# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XmlEmitter do
  describe ".escape_text" do
    it "escapes only & < > in a single pass" do
      expect(described_class.escape_text("a & < > ' \""))
        .to eq("a &amp; &lt; &gt; ' \"")
    end

    it "returns clean strings unallocated" do
      input = "clean"
      expect(described_class.escape_text(input)).to equal(input)
    end

    it "coerces non-strings" do
      expect(described_class.escape_text(1)).to eq("1")
    end
  end

  describe ".escape_attribute" do
    it "escapes & < > and double quotes, keeping apostrophes literal" do
      expect(described_class.escape_attribute(%q{& < > ' "}))
        .to eq("&amp; &lt; &gt; ' &quot;")
    end
  end

  describe ".cdata" do
    it "wraps content in a CDATA section" do
      expect(described_class.cdata("data")).to eq("<![CDATA[data]]>")
    end

    it "splits an embedded end sequence into adjacent sections" do
      expect(described_class.cdata("a]]>b"))
        .to eq("<![CDATA[a]]]]><![CDATA[>b]]>")
    end
  end

  describe ".declaration_xml" do
    it "renders only the set attributes" do
      expect(described_class.declaration_xml("1.0", nil, nil))
        .to eq('<?xml version="1.0"?>')
      expect(described_class.declaration_xml("1.0", "UTF-8", "yes"))
        .to eq('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    end

    it "omits empty encodings" do
      expect(described_class.declaration_xml("1.0", "", nil))
        .to eq('<?xml version="1.0"?>')
    end
  end

  describe ".doctype_xml" do
    it "renders PUBLIC and SYSTEM forms and bare names" do
      expect(described_class.doctype_xml("r", "pub", "sys"))
        .to eq('<!DOCTYPE r PUBLIC "pub" "sys">')
      expect(described_class.doctype_xml("r", nil, "sys"))
        .to eq('<!DOCTYPE r SYSTEM "sys">')
      expect(described_class.doctype_xml("r", nil, nil))
        .to eq("<!DOCTYPE r>")
    end
  end
end
