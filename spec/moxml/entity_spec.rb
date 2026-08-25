# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Entity do
  describe ".preprocess_entities" do
    it "marks non-standard entities and leaves the five standard ones" do
      marked = described_class.preprocess_entities("a &copy; b &amp; c &lt;")
      expect(marked).to include("#{described_class::MARKER}copy;")
      expect(marked).to include("&amp;")
      expect(marked).to include("&lt;")
    end

    it "returns the input untouched when it contains no ampersand" do
      input = "plain text"
      expect(described_class.preprocess_entities(input)).to equal(input)
    end

    it "always returns UTF-8" do
      binary = "caf\xC3\xA9 &copy;".b
      result = described_class.preprocess_entities(binary)
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it "returns an empty string for nil" do
      expect(described_class.preprocess_entities(nil)).to eq("")
    end
  end

  describe ".decode_entities" do
    it "decodes numeric and standard named references in one pass" do
      expect(described_class.decode_entities("&#65;&#x42;&amp;&lt;"))
        .to eq("AB&<")
    end

    it "preserves invalid numeric codepoints verbatim" do
      expect(described_class.decode_entities("&#0;&#xD800;")).to eq("&#0;&#xD800;")
    end

    it "skips strings without ampersands" do
      input = "plain"
      expect(described_class.decode_entities(input)).to equal(input)
    end
  end

  describe ".restore_entities" do
    it "maps markers back to named references" do
      restored = described_class.restore_entities(
        "a#{described_class::MARKER}copy;b",
      )
      expect(restored).to eq("a&copy;b")
    end

    it "restores markers a native serializer rendered as character references" do
      expect(described_class.restore_entities("a&#xFFFC;&#xFEFF;copy;b"))
        .to eq("a&copy;b")
    end

    it "returns marker-free strings without a regex pass" do
      input = "no markers here"
      expect(described_class.restore_entities(input)).to equal(input)
    end
  end

  describe Moxml::Entity::Reference do
    it "round-trips as a serialized entity reference" do
      expect(described_class.new("copy").to_xml).to eq("&copy;")
    end

    it "compares by name" do
      reference = described_class.new("copy")
      expect(reference).to eq(described_class.new("copy"))
      expect(reference).not_to eq(described_class.new("nbsp"))
    end
  end
end
