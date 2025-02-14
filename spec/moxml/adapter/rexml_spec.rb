# frozen_string_literal: true

require "rexml"
require "moxml/adapter/rexml"

RSpec.describe Moxml::Adapter::Rexml do
  around do |example|
    Moxml.with_config(:rexml, true, "UTF-8") do
      example.run
    end
  end

  it_behaves_like "xml adapter"

  describe "namespace handling" do
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope 
          xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xmlns:ns="urn:example:namespace">
          <soap:Header>
            <ns:SessionId>12345</ns:SessionId>
          </soap:Header>
          <soap:Body>
            <ns:GetUserRequest>
              <ns:UserId xsi:type="xsi:string">user123</ns:UserId>
            </ns:GetUserRequest>
          </soap:Body>
        </soap:Envelope>
      XML
    end

    it "preserves and correctly handles multiple namespaces" do
      # Parse original XML
      doc = described_class.parse(xml)
      
      # Test namespace preservation in serialization
      result = described_class.serialize(doc.native)
      expect(result).to include('xmlns:soap="http://www.w3.org/2003/05/soap-envelope"')
      expect(result).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(result).to include('xmlns:ns="urn:example:namespace"')
      
      # Test xpath with namespaces
      namespaces = {
        'soap' => 'http://www.w3.org/2003/05/soap-envelope',
        'ns' => 'urn:example:namespace'
      }
      
      # Find user ID using namespaced xpath
      user_id = described_class.at_xpath(doc, "//ns:UserId", namespaces)
      expect(described_class.text_content(user_id)).to eq('user123')
      
      # Verify soap:Body exists
      body = described_class.at_xpath(doc, "//soap:Body", namespaces)
      expect(body).not_to be_nil
      
      # Verify attribute with namespace
      expect(described_class.get_attribute_value(user_id, 'type')).to eq('xsi:string')
    end
  end
end
