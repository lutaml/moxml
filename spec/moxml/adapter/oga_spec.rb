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

  describe "namespace handling" do
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" 
          xmlns:atom="http://www.w3.org/2005/Atom"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Example RSS Feed</title>
            <atom:link href="http://example.com/feed" rel="self"/>
            <item>
              <title>Example Post</title>
              <dc:creator>John Doe</dc:creator>
              <content:encoded><![CDATA[<p>Post content</p>]]></content:encoded>
            </item>
          </channel>
        </rss>
      XML
    end

    it "preserves and correctly handles multiple namespaces" do
      # Parse original XML
      doc = described_class.parse(xml)
      
      # Test namespace preservation in serialization
      result = described_class.serialize(doc.native)
      expect(result).to include('xmlns:atom="http://www.w3.org/2005/Atom"')
      expect(result).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')
      expect(result).to include('xmlns:content="http://purl.org/rss/1.0/modules/content/"')
      
      # Test xpath with namespaces
      namespaces = {
        'atom' => 'http://www.w3.org/2005/Atom',
        'dc' => 'http://purl.org/dc/elements/1.1/',
        'content' => 'http://purl.org/rss/1.0/modules/content/'
      }
      
      # Find creator using namespaced xpath
      creator = described_class.at_xpath(doc, "//dc:creator", namespaces)
      expect(described_class.text_content(creator)).to eq('John Doe')
      
      # Verify atom:link exists
      link = described_class.at_xpath(doc, "//atom:link", namespaces)
      expect(link).not_to be_nil
      expect(described_class.get_attribute_value(link, 'href')).to eq('http://example.com/feed')
      
      # Verify CDATA in content:encoded
      content = described_class.at_xpath(doc, "//content:encoded", namespaces)
      expect(described_class.text_content(content)).to eq('<p>Post content</p>')
    end
  end
end
