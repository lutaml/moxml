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

  # The binding carries the face from 1.9.386.0 (engine 1.9.387);
  # published bindings below it loud-fail by contract, so the live
  # examples skip until the ride lands.
  def set_capable?
    defined?(Leptris::XML::XSD::Schema) &&
      Leptris::XML::XSD::Schema.respond_to?(:compile_set)
  end

  it "admits substitution members declared in importing documents" do
    skip "requires the leptris compile_set face (binding 1.9.386.0+)" unless
      set_capable?

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
    skip "requires the leptris compile_set face (binding 1.9.386.0+)" unless
      set_capable?

    Dir.mktmpdir do |dir|
      paths = write_set(dir)
      expect(ctx.xsd_set(paths)).to be_a(Moxml::XSD::Schema)
      expect(ctx.xsd_set(*paths)).to be_a(Moxml::XSD::Schema)
    end
  end

  # #510: the strict re-check answers "not declared" against the
  # head document's own declaration index; composition (a set, or a
  # single document carrying include/import/redefine/override)
  # means declarations may live in a member the index never saw —
  # the re-check must stay silent (under-report, never
  # false-report) and let the engine's set-wide answer stand.
  describe "strict re-check across composed schemas (#510)" do
    def write_wildcard_set(dir)
      File.write(File.join(dir, "headw.xsd"), <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns="urn:W" targetNamespace="urn:W">
          <xs:import namespace="urn:D" schemaLocation="decl.xsd"/>
          <xs:element name="foo">
            <xs:complexType>
              <xs:sequence>
                <xs:any namespace="##other" processContents="strict"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
      XSD
      File.write(File.join(dir, "decl.xsd"), <<~XSD)
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns="urn:D" targetNamespace="urn:D">
          <xs:element name="bar" type="xs:string"/>
        </xs:schema>
      XSD
      [File.join(dir, "headw.xsd"), File.join(dir, "decl.xsd")]
    end

    def wildcard_instance
      '<foo xmlns="urn:W" xmlns:d="urn:D"><d:bar>hi</d:bar></foo>'
    end

    it "does not false-report a member-declared admission on a set" do
      skip "requires the leptris compile_set face (binding 1.9.386.0+)" unless
        set_capable?

      Dir.mktmpdir do |dir|
        paths = write_wildcard_set(dir)
        schema = ctx.xsd_set(*paths)
        expect(schema.validate(wildcard_instance)).to be_empty
      end
    end

    it "does not false-report on a single composing document" do
      Dir.mktmpdir do |dir|
        write_wildcard_set(dir)
        schema = ctx.xsd_file(File.join(dir, "headw.xsd"))
        expect(schema.validate(wildcard_instance)).to be_empty
      end
    end

    it "keeps the re-check on a self-contained schema" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "solo.xsd")
        File.write(path, <<~XSD)
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                     xmlns="urn:S" targetNamespace="urn:S">
            <xs:element name="solo">
              <xs:complexType>
                <xs:sequence>
                  <xs:any namespace="##other" processContents="strict"/>
                </xs:sequence>
              </xs:complexType>
            </xs:element>
          </xs:schema>
        XSD
        schema = ctx.xsd_file(path)
        errors = schema.validate(
          '<solo xmlns="urn:S"><u:x xmlns:u="urn:U"/></solo>',
        )
        expect(errors.first.message)
          .to include("matches a strict wildcard but is not declared")
      end
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
