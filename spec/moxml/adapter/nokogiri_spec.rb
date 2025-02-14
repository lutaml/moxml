# frozen_string_literal: true

require "nokogiri"
require "moxml/adapter/nokogiri"

RSpec.describe Moxml::Adapter::Nokogiri do
  around do |example|
    Moxml.with_config(:nokogiri, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "namespace handling" do
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             xmlns:xlink="http://www.w3.org/1999/xlink"
             width="100" height="100">
          <defs>
            <circle id="myCircle" cx="50" cy="50" r="40"/>
          </defs>
          <use xlink:href="#myCircle" fill="red"/>
          <text x="50" y="50" text-anchor="middle">SVG</text>
        </svg>
      XML
    end

    it "preserves and correctly handles multiple namespaces" do
      # Parse original XML
      doc = described_class.parse(xml)
      
      # Test namespace preservation in serialization
      result = described_class.serialize(doc.native)
      expect(result).to include('xmlns="http://www.w3.org/2000/svg"')
      expect(result).to include('xmlns:xlink="http://www.w3.org/1999/xlink"')
      
      # Test xpath with namespaces
      namespaces = {
        'svg' => 'http://www.w3.org/2000/svg',
        'xlink' => 'http://www.w3.org/1999/xlink'
      }
      
      # Find use element and verify xlink:href attribute
      use_elem = described_class.at_xpath(doc, "//svg:use", namespaces)
      expect(use_elem).not_to be_nil
      expect(described_class.get_attribute_value(use_elem, 'href')).to eq('#myCircle')
      
      # Verify circle element exists in defs
      circle = described_class.at_xpath(doc, "//svg:defs/svg:circle", namespaces)
      expect(circle).not_to be_nil
      expect(described_class.get_attribute_value(circle, 'id')).to eq('myCircle')
      
      # Test default SVG namespace
      text = described_class.at_xpath(doc, "//svg:text", namespaces)
      expect(described_class.text_content(text)).to eq('SVG')
    end
  end
end
