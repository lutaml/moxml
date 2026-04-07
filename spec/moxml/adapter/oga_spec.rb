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
      serialized = doc.to_xml
      # After round-trip, the entity reference should be preserved
      expect(serialized).to include("&nbsp;")
      expect(serialized).to include("Item")
      expect(serialized).to include("One")
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
      serialized = doc.to_xml

      # All entities should be preserved in round-trip
      expect(serialized).to include("&nbsp;")
      expect(serialized).to include("&mdash;")
      expect(serialized).to include("&lsquo;")
    end
  end
end
