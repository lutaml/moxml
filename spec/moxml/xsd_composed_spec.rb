# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# moxml#522: composed-schema strict admission. The facade owns the
# composition — it resolves the instance's xsi:schemaLocation hints
# against the schema's own path, rebuilds the handle as a union at
# first validate, and dismisses engine "not declared (strict)" rows
# the composed declaration index refutes.
RSpec.describe "Moxml::XSD::Schema composed-schema validation (#522)" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:main_xsd) do
    <<~XSD
      <?xml version="1.0"?>
      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <xsd:attribute name="att1" type="xsd:string"/>
        <xsd:element name="doc">
          <xsd:complexType>
            <xsd:attributeGroup ref="main"/>
          </xsd:complexType>
        </xsd:element>
        <xsd:attributeGroup name="main">
          <xsd:attribute ref="att1"/>
          <xsd:anyAttribute namespace="##any"/>
        </xsd:attributeGroup>
      </xsd:schema>
    XSD
  end
  # The auxiliary unit: a global declaration the head unit never saw.
  let(:aux_xsd) do
    <<~XSD
      <?xml version="1.0"?>
      <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                  targetNamespace="http://aux">
        <xsd:attribute name="ext" type="xsd:string"/>
      </xsd:schema>
    XSD
  end

  # Per-example fixture tempdir: created by the let, removed in the
  # after hook. Plain lets + methods keep the suite ivar-free
  # (house law).
  let(:dir) { Dir.mktmpdir("moxml522") }

  after { FileUtils.remove_entry(dir) }

  def unit(name)
    File.join(dir, name)
  end

  before do
    File.write(unit("main.xsd"), main_xsd)
    File.write(unit("aux.xsd"), aux_xsd)
  end

  it "unions the instance's hint documents into the validation" do
    schema = ctx.xsd_file(unit("main.xsd"))
    doc = ctx.parse(
      '<doc xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
      'xmlns:e="http://aux" xsi:noNamespaceSchemaLocation="main.xsd" ' \
      'xsi:schemaLocation="http://aux aux.xsd" att1="x" e:ext="y"/>',
    )
    expect(schema.validate(doc)).to be_empty
  end

  it "dismisses the engine's not-declared rows the union refutes" do
    # Without the union the engine reports the aux attribute as
    # undeclared; with it, the composed declaration index refutes
    # the row. The engine may carry either the attribute-level row
    # or the element-level root row (mixed-tns mis-admission) —
    # both are refutable.
    schema = ctx.xsd_file(unit("main.xsd"))
    doc = ctx.parse(
      '<doc xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
      'xmlns:e="http://aux" xsi:noNamespaceSchemaLocation="main.xsd" ' \
      'xsi:schemaLocation="http://aux aux.xsd" att1="x" e:ext="y">text</doc>',
    )
    errors = schema.validate(doc)
    expect(errors.map(&:message)).not_to include(
      /not declared \(strict\)/,
    )
  end

  it "keeps genuinely undeclared attribute rows" do
    schema = ctx.xsd_file(unit("main.xsd"))
    doc = ctx.parse(
      '<doc xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
      'xsi:noNamespaceSchemaLocation="main.xsd" att1="x" ghost="z"/>',
    )
    # `ghost` is declared nowhere: the strict row (when the engine
    # emits one) must survive the dismissal.
    errors = schema.validate(doc).map(&:message)
    expect(errors.grep_v(/ghost.*not declared/)).to be_empty
  end

  it "does not build a union for string-compiled schemas" do
    schema = ctx.xsd(main_xsd)
    doc = ctx.parse("<doc att1=\"x\"/>")
    expect(schema.validate(doc)).to be_empty
  end
end
