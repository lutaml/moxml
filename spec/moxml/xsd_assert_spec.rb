# frozen_string_literal: true

require "spec_helper"

# moxml#556: XSD 1.1 xs:assert was compiled but never evaluated —
# assertion-violating instances validated clean. Two defects: the
# versioning namespace constant read 2001 (the spec says 2007), so
# vc:minVersion="1.1" never triggered 1.1 semantics, and the asserts
# were indexed but not evaluated. The evaluation rides the pure-Ruby
# XPath compiler over the element context; an unevaluatable test
# (an XPath 2.0 construct the compiler does not carry) under-reports
# silently — the one-directional contract never false-reports.
# The engine-compile lane has a separate finding: an assert-carrying
# schema compiled under rspec's boot state fails (status -2, both
# attempts) - filed to leptris-ruby. The evaluation contract is
# engine-free: SchemaRules.findings evaluates the indexed asserts via
# the pure-Ruby XPath compiler.
RSpec.describe "XSD 1.1 xs:assert evaluation" do
  let(:ctx) { Moxml::Context.new(:leptris) }

  let(:schema) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" vc:minVersion="1.1"
        xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning">
        <xs:element name="doc">
          <xs:complexType>
            <xs:sequence><xs:element name="a" type="xs:int" maxOccurs="unbounded"/></xs:sequence>
            <xs:assert test="sum(a) > 0"/>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  def findings_for(instance_xml, schema_xml = schema)
    index = Moxml::XSD::SchemaRules.index(schema_xml, ctx)
    doc = ctx.parse(instance_xml)
    Moxml::XSD::SchemaRules.findings(doc, index)
  end

  it "indexes the schema version as 1.1 for the 2007 namespace" do
    index = Moxml::XSD::SchemaRules.index(schema, ctx)
    expect(index.version).to eq("1.1")
  end

  it "accepts an instance the assertion holds for" do
    expect(findings_for("<doc><a>5</a></doc>")).to be_empty
  end

  it "rejects an instance the assertion fails for" do
    errors = findings_for("<doc><a>-5</a></doc>")
    expect(errors).not_to be_empty
    expect(errors.first.message).to include("assertion")
  end

  it "binds the assert's prefixes against the schema's namespaces" do
    prefixed_schema = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning"
        xmlns:t="urn:t" vc:minVersion="1.1" targetNamespace="urn:t"
        elementFormDefault="qualified">
        <xs:element name="doc">
          <xs:complexType>
            <xs:sequence><xs:element name="a" type="xs:int"/></xs:sequence>
            <xs:assert test="t:a[@t:k]"/>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    expect(findings_for('<t:doc xmlns:t="urn:t"><t:a t:k="present"/></t:doc>',
                        prefixed_schema)).to be_empty
    expect(findings_for('<t:doc xmlns:t="urn:t"><t:a/></t:doc>',
                        prefixed_schema)).not_to be_empty
  end

  it "under-reports silently when the test is unevaluatable" do
    unevaluatable = <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:vc="http://www.w3.org/2007/XMLSchema-versioning" vc:minVersion="1.1">
        <xs:element name="doc">
          <xs:complexType>
            <xs:sequence><xs:element name="a" type="xs:int"/></xs:sequence>
            <xs:assert test="for $x in a return $x"/>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
    expect(findings_for("<doc><a>5</a></doc>", unevaluatable)).to be_empty
  end
end
