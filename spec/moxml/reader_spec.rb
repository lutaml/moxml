# frozen_string_literal: true

require "spec_helper"

# lutaml/moxml#582 gap 4: the streaming Reader — Nokogiri::XML::Reader
# parity for memory-conscious consumers (ea's large-XMI extractors):
# a pull walk over the adapter's streaming face with node types,
# names, values, attributes, depth, empty-element detection, and the
# subtree serialization. Engines without a streaming face raise
# loudly (the loud-degradation clause).
RSpec.describe Moxml::Reader do
  let(:xml) do
    <<~XML
      <?xml version="1.0"?>
      <catalog>
        <book id="b1" lang="en">
          <title>A title</title>
          <meta empty="yes"/>
        </book>
        <book id="b2"/>
      </catalog>
    XML
  end

  describe "the pull walk" do
    it "visits elements, text, and end markers in document order" do
      reader = described_class.new(xml, :leptris)
      visits = []
      while reader.read
        visits << [reader.node_type, reader.name, reader.value, reader.node_depth]
      end

      visits.map { |_v| described_class::TYPE_ELEMENT }
      expect(visits.first).to eq([described_class::TYPE_ELEMENT, "catalog", nil, 0])

      # the second book's start element carries its attributes
      book2 = visits.find { |v| v[1] == "book" && v[3] == 1 && v != visits[1] }
      expect(book2).not_to be_nil
    end

    it "exposes attributes on start elements" do
      reader = described_class.new(xml, :leptris)
      found = nil
      while reader.read
        if reader.node_type == described_class::TYPE_ELEMENT &&
            reader.name == "book" && reader["id"] == "b1"
          found = reader.attributes
          break
        end
      end

      expect(found).to eq({ "id" => "b1", "lang" => "en" })
    end

    it "surfaces text values" do
      reader = described_class.new(xml, :leptris)
      title_text = nil
      while reader.read
        if reader.node_type == described_class::TYPE_TEXT &&
            reader.value&.include?("A title")
          title_text = reader.value
        end
      end

      expect(title_text).to include("A title")
    end

    it "flags empty elements" do
      reader = described_class.new(xml, :leptris)
      empties = []
      while reader.read
        empties << reader.name if reader.empty_element?
      end

      expect(empties).to include("meta")
      expect(empties).to include("book")
    end

    it "serializes the current subtree with outer_xml" do
      reader = described_class.new(xml, :leptris)
      snippet = nil
      while reader.read
        if reader.node_type == described_class::TYPE_ELEMENT &&
            reader.name == "book" && reader["id"] == "b1"
          snippet = reader.outer_xml
          break
        end
      end

      expect(snippet).to include("<book")
      expect(snippet).to include('id="b1"')
      expect(snippet).to include("A title")
      expect(snippet).to include("</book>")
    end

    it "ends with read returning nil" do
      reader = described_class.new(xml, :leptris)
      count = 0
      count += 1 while reader.read

      expect(count).to be_positive
      expect(reader.read).to be_nil
    end
  end

  describe "engine gating" do
    it "raises loudly on engines without a streaming face" do
      expect { described_class.new(xml, :ox) }
        .to raise_error(Moxml::NotImplementedError, /streaming|Reader/i)
    end
  end
end
