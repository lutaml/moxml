# frozen_string_literal: true

# Processing model §Validation (normative): pinned here.

require "spec_helper"

RSpec.describe "Schema-set compilation" do
  let(:ctx) { Moxml.new(:leptris) }

  # leptris#1881 / moxml#483 item 4: a head document cannot see
  # substitution-group members declared in schemas that import it;
  # the set face merges every document into one compilation.
  def write_set(dir)
    File.write(File.join(dir, "f.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns="urn:F" xmlns:f="urn:F" targetNamespace="urn:F"
                 elementFormDefault="qualified">
        <xs:complexType name="foo">
          <xs:sequence><xs:any/></xs:sequence>
        </xs:complexType>
        <xs:element name="foo" type="foo"/>
        <xs:element name="bar">
          <xs:complexType>
            <xs:choice minOccurs="0" maxOccurs="unbounded">
              <xs:element ref="f:foo"/>
              <xs:element ref="f:bar"/>
            </xs:choice>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    File.write(File.join(dir, "g.xsd"), <<~XSD)
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns:g="urn:G" xmlns:f="urn:F" targetNamespace="urn:G"
                 elementFormDefault="qualified">
        <xs:import namespace="urn:F" schemaLocation="f.xsd"/>
        <xs:element name="foo1" substitutionGroup="f:foo">
          <xs:complexType>
            <xs:complexContent>
              <xs:extension base="f:foo">
                <xs:attribute name="x" type="xs:int"/>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    [File.join(dir, "f.xsd"), File.join(dir, "g.xsd")]
  end

  it "admits substitution members declared in importing documents" do
    Dir.mktmpdir do |dir|
      paths = write_set(dir)
      schema = ctx.xsd_set(*paths)
      doc = ctx.parse(
        '<f:foo xmlns:f="urn:F" xmlns:g="urn:G">' \
        '<f:bar><g:foo1 x="1"><f:bar/></g:foo1></f:bar></f:foo>',
      )
      expect(schema.validate(doc)).to be_empty
    end
  end

  it "accepts the paths as an array or as arguments" do
    Dir.mktmpdir do |dir|
      paths = write_set(dir)
      expect(ctx.xsd_set(paths)).to be_a(Moxml::XSD::Schema)
      expect(ctx.xsd_set(*paths)).to be_a(Moxml::XSD::Schema)
    end
  end

  it "raises on an empty set" do
    expect { ctx.xsd_set }.to raise_error(ArgumentError)
  end

  it "raises the named error on adapters without a set-capable engine" do
    nk = Moxml.new(:nokogiri)
    Dir.mktmpdir do |dir|
      paths = write_set(dir)
      expect { nk.xsd_set(*paths) }
        .to raise_error(Moxml::NotImplementedError, /compile_set face/)
    end
  end
end
