# spec/moxml/declaration_spec.rb
RSpec.describe Moxml::Declaration do
  let(:context) { Moxml.new }
  let(:doc) { context.create_document }
  let(:declaration) { doc.create_declaration("1.0", "UTF-8", "yes") }

  it "identifies as declaration node" do
    expect(declaration).to be_declaration
  end

  describe "version handling" do
    it "gets version" do
      expect(declaration.version).to eq("1.0")
    end

    it "sets version" do
      declaration.version = "1.1"
      expect(declaration.version).to eq("1.1")
    end

    it "validates version" do
      expect { declaration.version = "2.0" }
        .to raise_error(Moxml::ValidationError, "Invalid XML version: 2.0")
    end
  end

  describe "encoding handling" do
    it "gets encoding" do
      expect(declaration.encoding).to eq("UTF-8")
    end

    it "sets encoding" do
      declaration.encoding = "ISO-8859-1"
      expect(declaration.encoding).to eq("ISO-8859-1")
    end

    it "normalizes encoding" do
      declaration.encoding = "utf-8"
      expect(declaration.encoding).to eq("utf-8")
    end
  end

  describe "standalone handling" do
    it "gets standalone" do
      expect(declaration.standalone).to eq("yes")
    end

    it "sets standalone" do
      declaration.standalone = "no"
      expect(declaration.standalone).to eq("no")
    end

    it "validates standalone value" do
      expect { declaration.standalone = "maybe" }
        .to raise_error(Moxml::ValidationError, "Invalid standalone value: maybe")
    end

    it "allows nil standalone" do
      declaration.standalone = nil
      expect(declaration.standalone).to be_nil
    end
  end

  describe "serialization" do
    it "formats complete declaration" do
      expect(declaration.to_xml).to eq('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    end

    it "formats minimal declaration with empty encoding" do
      decl = doc.create_declaration("1.0", nil)
      expect(decl.to_xml).to eq('<?xml version="1.0"?>')
    end

    it "formats declaration with encoding only" do
      decl = doc.create_declaration("1.0", "UTF-8")
      expect(decl.to_xml).to eq('<?xml version="1.0" encoding="UTF-8"?>')
    end
  end

  describe "node operations" do
    it "adds to document" do
      doc.add_child(declaration)
      expect(doc.to_xml).to start_with("<?xml")
    end

    it "removes from document" do
      doc.add_child(declaration)
      declaration.remove
      # the document contains a default declaration
      expect(doc.to_xml).not_to include("<?xml")
    end
  end
end
