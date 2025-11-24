# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML Declaration Preservation" do
  # Test with all available adapters
  ADAPTERS = %i[nokogiri oga rexml ox libxml headed_ox].freeze

  ADAPTERS.each do |adapter_name|
    context "with #{adapter_name} adapter" do
      let(:context) { Moxml.new(adapter_name) }

      describe "automatic preservation" do
        context "when input has no XML declaration" do
          let(:xml_without_decl) { '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' }

          it "does not add XML declaration to output" do
            doc = context.parse(xml_without_decl)
            output = doc.to_xml

            expect(output).not_to include("<?xml")
            expect(output).to include("<svg")
          end

          it "sets has_xml_declaration to false" do
            doc = context.parse(xml_without_decl)
            expect(doc.has_xml_declaration).to be false
          end
        end

        context "when input has XML declaration" do
          let(:xml_with_decl) do
            '<?xml version="1.0" encoding="UTF-8"?><root><child/></root>'
          end

          it "preserves XML declaration in output" do
            doc = context.parse(xml_with_decl)
            output = doc.to_xml

            expect(output).to include("<?xml")
            expect(output).to include('version="1.0"')
          end

          it "sets has_xml_declaration to true" do
            doc = context.parse(xml_with_decl)
            expect(doc.has_xml_declaration).to be true
          end
        end

        context "when input has declaration with standalone attribute" do
          let(:xml_with_standalone) do
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><root/>'
          end

          it "preserves the declaration" do
            doc = context.parse(xml_with_standalone)
            output = doc.to_xml

            expect(output).to include("<?xml")
          end
        end
      end

      describe "explicit override" do
        let(:xml_without_decl) { "<root><child/></root>" }
        let(:xml_with_decl) { '<?xml version="1.0"?><root><child/></root>' }

        context "when forcing declaration on document without one" do
          it "adds declaration when declaration: true" do
            doc = context.parse(xml_without_decl)
            output = doc.to_xml(declaration: true)

            expect(output).to include("<?xml")
          end
        end

        context "when removing declaration from document with one" do
          it "removes declaration when declaration: false" do
            doc = context.parse(xml_with_decl)
            output = doc.to_xml(declaration: false)

            expect(output).not_to include("<?xml")
            expect(output).to include("<root")
          end
        end

        context "when explicitly preserving declaration" do
          it "keeps declaration when declaration: true" do
            doc = context.parse(xml_with_decl)
            output = doc.to_xml(declaration: true)

            expect(output).to include("<?xml")
          end
        end
      end

      describe "round-trip fidelity" do
        context "for document without declaration" do
          let(:original) { "<root><item id=\"1\"/></root>" }

          it "maintains absence of declaration through parse and serialize" do
            doc = context.parse(original)
            output = doc.to_xml

            expect(output).not_to include("<?xml")

            # Parse again and verify
            doc2 = context.parse(output)
            expect(doc2.has_xml_declaration).to be false
          end
        end

        context "for document with declaration" do
          let(:original) do
            '<?xml version="1.0" encoding="UTF-8"?><root><item id="1"/></root>'
          end

          it "maintains presence of declaration through parse and serialize" do
            doc = context.parse(original)
            output = doc.to_xml

            expect(output).to include("<?xml")

            # Parse again and verify
            doc2 = context.parse(output)
            expect(doc2.has_xml_declaration).to be true
          end
        end
      end

      describe "edge cases" do
        context "with empty document" do
          it "does not add declaration to empty document" do
            doc = context.create_document

            # Empty documents should not have declaration by default
            expect(doc.has_xml_declaration).to be false
          end
        end

        context "with built document" do
          it "does not add declaration to programmatically built document" do
            doc = context.create_document
            root = doc.create_element("root")
            doc.root = root

            output = doc.to_xml

            expect(output).not_to include("<?xml")
            expect(doc.has_xml_declaration).to be false
          end

          it "can explicitly add declaration to built document" do
            doc = context.create_document
            root = doc.create_element("root")
            doc.root = root

            output = doc.to_xml(declaration: true)

            expect(output).to include("<?xml")
          end
        end
      end

      describe "non-document nodes" do
        let(:xml) { '<?xml version="1.0"?><root><child>text</child></root>' }

        it "does not add declaration when serializing element nodes" do
          doc = context.parse(xml)
          root = doc.root
          output = root.to_xml

          expect(output).not_to include("<?xml")
          expect(output).to include("<root>")
        end
      end
    end
  end

  describe "integration with svg_conform use case" do
    let(:context) { Moxml.new }

    context "remediating SVG without declaration" do
      let(:svg_input) { '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect x="10" y="10" width="80" height="80"/></svg>' }

      it "does not add declaration to remediated output" do
        doc = context.parse(svg_input)

        # Simulate remediation: add viewport
        root = doc.root
        root["viewBox"] = "0 0 100 100"

        output = doc.to_xml

        expect(output).not_to include("<?xml")
        expect(output).to include('viewBox="0 0 100 100"')
      end
    end

    context "remediating SVG with declaration" do
      let(:svg_input) { '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' }

      it "preserves declaration in remediated output" do
        doc = context.parse(svg_input)

        # Simulate remediation
        root = doc.root
        root["viewBox"] = "0 0 100 100"

        output = doc.to_xml

        expect(output).to include("<?xml")
        expect(output).to include('viewBox="0 0 100 100"')
      end
    end
  end
end
