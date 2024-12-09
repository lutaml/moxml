RSpec.shared_examples 'Moxml::Builder' do
  let(:context) { Moxml.new }
  let(:builder) { Moxml::Builder.new(context) }

  describe "#document" do
    it "creates a well-formed document" do
      doc = builder.build do
        declaration version: "1.0", encoding: "UTF-8"
        element "root" do
          element "child", id: "1" do
            text "content"
          end
        end
      end

      xml = doc.to_xml
      expect(xml).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(xml).to include("<root>")
      expect(xml).to include('<child id="1">content</child>')
      expect(xml).to include("</root>")
    end
  end
end
