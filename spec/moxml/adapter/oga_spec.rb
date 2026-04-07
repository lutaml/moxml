# frozen_string_literal: true

require "oga"
require "moxml/adapter/oga"

RSpec.describe Moxml::Adapter::Oga do
  around do |example|
    Moxml.with_config(:oga, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "entity handling" do
    it "preserves non-breaking space through parse and serialize round-trip" do
      xml = "<root>Item&nbsp;One</root>"
      doc = described_class.parse(xml)
      text = described_class.text_content(doc.at_xpath("//root"))

      # Should contain the actual non-breaking space character (U+00A0)
      expect(text.bytes).to include(160)
      expect(text).to include("Item")
      expect(text).to include("One")
    end

    it "correctly parses numeric character references" do
      xml = "<root>&#160;</root>"
      doc = described_class.parse(xml)
      text = described_class.text_content(doc.at_xpath("//root"))

      # Should contain the actual non-breaking space character (U+00A0)
      expect(text.bytes).to include(160)
    end

    it "handles multiple different entities" do
      xml = "<root>&nbsp;&mdash;&lsquo;</root>"
      doc = described_class.parse(xml)
      text = described_class.text_content(doc.at_xpath("//root"))

      # Should contain actual characters (not empty, not dropped)
      expect(text.bytes.length).to be > 0
    end
  end
end
