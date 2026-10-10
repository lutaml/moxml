# frozen_string_literal: true

require "spec_helper"

# Moxml::XSD contract (leptris tier-1 faces): compile + validate
# with accumulated errors; unsupported adapters raise
# NotImplementedError at compile.
RSpec.describe Moxml::XSD do
  let(:ctx) { Moxml.new(:leptris) }
  let(:schema_text) do
    <<~XSD
      <?xml version="1.0"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="note" type="t_note"/>
        <xs:complexType name="t_note">
          <xs:sequence>
            <xs:element name="to" type="t_string"/>
          </xs:sequence>
        </xs:complexType>
        <xs:simpleType name="t_string">
          <xs:restriction base="xs:string"/>
        </xs:simpleType>
      </xs:schema>
    XSD
  end

  it "reports supported? on the leptris adapter" do
    skip "leptris adapter unavailable" unless
      Moxml::Adapter::Leptris::XSD_SUPPORTED

    expect(described_class.supported?(ctx)).to be(true)
  end

  context "when the adapter ships a validator" do
    before do
      skip "leptris 1.9.321+ engine required" unless
        Moxml::Adapter::Leptris::XSD_SUPPORTED
    end

    it "compiles and validates a good document" do
      schema = ctx.xsd(schema_text)
      doc = ctx.parse("<note><to>You</to></note>")
      expect(schema.valid?(doc)).to be(true)
      expect(schema.validate(doc)).to eq([])
    end

    it "returns accumulated messages for an invalid document" do
      schema = ctx.xsd(schema_text)
      errors = schema.validate("<note><wrong/></note>")
      expect(errors).not_to be_empty
    end

    it "validates raw XML strings and nodes" do
      schema = ctx.xsd(schema_text)
      doc = ctx.parse("<note><to>x</to></note>")
      expect(schema.valid?(doc.root)).to be(true)
      expect(schema.valid?("<note><to>x</to></note>")).to be(true)
      expect(schema.valid?("<note><wrong/></note>")).to be(false)
    end

    it "surfaces the lexical, census, and content faces" do
      schema = ctx.xsd(schema_text)
      expect(schema.declarations).to be >= 2
      expect(schema.compile_error).to be_nil
      expect(schema.simple_valid?("t_string", "abc")).to be(true)
    end

    it "checks built-in lexical forms" do
      expect(described_class.builtin_valid?(ctx, "xs:integer", "3")).to be(true)
      expect(described_class.builtin_valid?(ctx, "xs:integer", "x")).to be(false)
      expect do
        described_class.builtin_valid?(ctx, "xs:nope", "3")
      end.to raise_error(ArgumentError)
    end

    it "checks content models through moxml nodes" do
      schema = ctx.xsd(schema_text)
      doc = ctx.parse("<note><to>You</to></note>")
      expect(schema.content_valid?("note", [doc.at("//to")])).to be(true)
      expect(schema.content_valid?("note", [])).to be(false)
    end

    it "compiles from a file with relative includes" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "main.xsd"), <<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:include schemaLocation="inc.xsd"/>
          </xs:schema>
        XSD
        File.write(File.join(dir, "inc.xsd"), <<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:element name="note" type="xs:string"/>
          </xs:schema>
        XSD
        schema = ctx.xsd_file(File.join(dir, "main.xsd"))
        # The include pulled the declaration in (both files' schema
        # elements census).
        expect(schema.declarations).to be >= 1
        expect(schema.valid?("<note>x</note>")).to be(true)
      end
    end

    it "memoizes the parse for frozen string sources (moxml#350)" do
      schema = ctx.xsd(schema_text)
      source = "<note><to>You</to></note>"
      first = schema.validate(source)
      parsed = schema.instance_variable_get(:@parsed_source)
      expect(parsed[0]).to equal(source)
      3.times { schema.validate(source) }
      # same source object, one parse — the memo entry is untouched
      expect(schema.instance_variable_get(:@parsed_source)[1])
        .to equal(parsed[1])
      expect(first).to eq([])
    end

    it "re-parses unfrozen string sources (mutation stays visible)" do
      schema = ctx.xsd(schema_text)
      mutable = +"<note><to>You</to></note>"
      expect(schema.valid?(mutable)).to be(true)
      mutable.replace("<note><wrong/></note>")
      expect(schema.valid?(mutable)).to be(false)
      expect(schema.instance_variable_get(:@parsed_source)).to be_nil
    end

    it "derives XSD_SUPPORTED from the engine face gate" do
      # The capability flag must not outrun the engine faces: a
      # misreleased lockstep (NATIVE_PLAN_STRUCTS lesson) would arm
      # compile against missing functions.
      expect(Moxml::Adapter::Leptris::XSD_SUPPORTED)
        .to eq(Moxml::Adapter::Leptris::NATIVE_XSD)
    end
  end
end
