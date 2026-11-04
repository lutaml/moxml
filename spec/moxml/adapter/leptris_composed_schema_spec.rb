# frozen_string_literal: true

require "spec_helper"

require "tempfile"

# moxml#522 re-audit on the current stack: the three composed-schema
# families (attribute admission through included attributeGroups,
# chameleon type binding, substitution heads across includes) all
# validate through the composition-capable faces — xsd_file (the
# engine resolves schemaLocation against the file's directory) and
# compile_set. The bare STRING face cannot chase files, so it
# refuses composition with actionable guidance instead of the
# misleading "not declared (strict)" cascade (#522's original
# evidence).
RSpec.describe "composed-schema validation (moxml#522)" do
  let(:ctx) { Moxml.new(:leptris) }

  def with_schema_dir(&block)
    dir = Dir.mktmpdir
    File.write(File.join(dir, "group.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:attributeGroup name="g">
          <xs:attribute name="foo" type="xs:string"/>
          <xs:attribute name="bar" type="xs:integer"/>
        </xs:attributeGroup>
        <xs:element name="head" type="xs:string"/>
      </xs:schema>
    XSD
    File.write(File.join(dir, "doc.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:include schemaLocation="group.xsd"/>
        <xs:element name="doc">
          <xs:complexType>
            <xs:attributeGroup ref="g"/>
          </xs:complexType>
        </xs:element>
        <xs:element name="container">
          <xs:complexType>
            <xs:sequence>
              <xs:element ref="head"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
        <xs:element name="member" type="xs:string"
                    substitutionGroup="head"/>
      </xs:schema>
    XSD
    yield dir
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  context "with the composition-capable faces" do
    it "validates attributeGroup composition across an include" do
      with_schema_dir do |dir|
        schema = ctx.xsd_file(File.join(dir, "doc.xsd"))
        expect(schema).to be_valid(%(<doc foo="hello" bar="42"/>))
      end
    end

    it "validates a substitution member under an included head" do
      with_schema_dir do |dir|
        schema = ctx.xsd_file(File.join(dir, "doc.xsd"))
        expect(schema).to be_valid(%(<container><member>v</member></container>))
      end
    end

    it "rejects a non-member where the head is required" do
      with_schema_dir do |dir|
        schema = ctx.xsd_file(File.join(dir, "doc.xsd"))
        expect(schema).not_to be_valid(
          %(<container><stranger>v</stranger></container>),
        )
      end
    end

    it "validates chameleon type binding through compile_set" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "types.xsd"), <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="code">
            <xs:restriction base="xs:string">
              <xs:pattern value="[A-Z]{3}"/>
            </xs:restriction>
          </xs:simpleType>
        </xs:schema>
      XSD
      File.write(File.join(dir, "cham.xsd"), <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:d" xmlns:d="urn:d"
                   elementFormDefault="qualified">
          <xs:include schemaLocation="types.xsd"/>
          <xs:element name="a1" type="d:code"/>
        </xs:schema>
      XSD
      schema = ctx.xsd_set(File.join(dir, "types.xsd"),
                           File.join(dir, "cham.xsd"))
      expect(schema).to be_valid(%(<a1 xmlns="urn:d">ABC</a1>))
    ensure
      FileUtils.remove_entry(dir) if dir
    end
  end

  context "with the bare string face" do
    it "refuses composition with actionable guidance" do
      source = <<~XSD
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:include schemaLocation="group.xsd"/>
          <xs:element name="doc" type="xs:string"/>
        </xs:schema>
      XSD
      expect { ctx.xsd(source) }
        .to raise_error(ArgumentError, %r{xsd_file|compile_set})
    end

    it "keeps accepting self-contained sources" do
      schema = ctx.xsd(<<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="doc" type="xs:string"/>
        </xs:schema>
      XSD
      expect(schema).to be_valid(%(<doc>hi</doc>))
    end
  end
end
