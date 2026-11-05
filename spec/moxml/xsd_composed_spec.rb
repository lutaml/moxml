# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

# moxml#522: composed-schema strict admission. The facade owns the
# composition — it resolves the instance's xsi:schemaLocation hints
# against the schema's own path, walks the schema graph
# (include/import/redefine) for the unit closure, and dismisses
# engine "not declared (strict)" rows the composed declaration index
# refutes — global declarations AND attributeGroup members. The
# engine admission gap itself is RESOLVED in leptris 1.9.409
# (leptris#1964 — register entry D-23). The 1.9.409 namespace-aware
# particle wave carries an upstream schG2 lexical regression
# (leptris#1976 — register entry D-24); its rows are lexical, not
# admission rows, and pass through untouched here.
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

  # The attgC class (moxml#522): the attribute is a member of an
  # attributeGroup reached through xs:redefine (the body hooks the
  # original with a self-ref — 4.2.2) and an import. The instance
  # carries no xsi hints; the composed unit closure must see the
  # redefined/imported documents through the schema graph alone.
  describe "group-member admission through the schema graph" do
    let(:group_xsd) do
      <<~XSD
        <?xml version="1.0"?>
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    xmlns:imp="http://imported">
          <xsd:import namespace="http://imported" schemaLocation="group.imp"/>
          <xsd:redefine schemaLocation="group.red">
            <xsd:attributeGroup name="car">
              <xsd:attributeGroup ref="car"/>
              <xsd:attributeGroup ref="imp:bar"/>
            </xsd:attributeGroup>
          </xsd:redefine>
          <xsd:element name="doc" type="test"/>
          <xsd:complexType name="test">
            <xsd:attributeGroup ref="car"/>
          </xsd:complexType>
        </xsd:schema>
      XSD
    end
    let(:group_red_xsd) do
      <<~XSD
        <?xml version="1.0"?>
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:attributeGroup name="car">
            <xsd:attribute name="att1" type="xsd:int"/>
          </xsd:attributeGroup>
        </xsd:schema>
      XSD
    end
    let(:group_imp_xsd) do
      <<~XSD
        <?xml version="1.0"?>
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    targetNamespace="http://imported">
          <xsd:attributeGroup name="bar">
            <xsd:attribute name="att4" type="xsd:int"/>
          </xsd:attributeGroup>
        </xsd:schema>
      XSD
    end

    before do
      File.write(unit("group.xsd"), group_xsd)
      File.write(unit("group.red"), group_red_xsd)
      File.write(unit("group.imp"), group_imp_xsd)
    end

    it "admits redefined and imported group members on the element" do
      schema = ctx.xsd_file(unit("group.xsd"))
      doc = ctx.parse(
        '<doc xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
        'xmlns:imp="http://imported" ' \
        'xsi:noNamespaceSchemaLocation="group.xsd" att1="1" imp:att4="2"/>',
      )
      expect(schema.validate(doc)).to be_empty
    end

    it "keeps rows for attributes no unit of the composition declares" do
      schema = ctx.xsd_file(unit("group.xsd"))
      doc = ctx.parse(
        '<doc xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
        'xsi:noNamespaceSchemaLocation="group.xsd" att1="1" ghost="z"/>',
      )
      errors = schema.validate(doc).map(&:message)
      expect(errors.grep_v(/ghost.*not declared/)).to be_empty
    end
  end
end
