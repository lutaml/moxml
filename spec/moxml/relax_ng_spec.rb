# frozen_string_literal: true

require "spec_helper"
require "tempfile"

# RELAX NG facade (TODO.sota/05): engines with an RNG validator
# answer valid?/validate/validate_errors; engines without one raise
# the named NotImplementedError at compile and answer supported?
# without raising.
RSpec.describe Moxml::RelaxNG do
  RNG_SCHEMA = <<~RNG # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
    <element name="r" xmlns="http://relaxng.org/ns/structure/1.0">
      <attribute name="a"><text/></attribute>
    </element>
  RNG

  let(:valid_doc) { Moxml.new(:leptris).parse('<r a="x"/>') }
  let(:invalid_doc) { Moxml.new(:leptris).parse("<r/>") }

  it "answers supported? without raising on every adapter" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
      ctx = Moxml.new(name)
      expect { described_class.supported?(ctx) }.not_to raise_error
    end
  end

  it "validates against a compiled schema and reports findings" do
    ctx = Moxml.new(:leptris)
    skip "leptris binding has no RNG face" unless described_class.supported?(ctx)

    schema = ctx.relaxng(RNG_SCHEMA)
    expect(schema.valid?(valid_doc)).to be(true)
    expect(schema.validate(valid_doc)).to eq([])
    expect(schema.valid?(invalid_doc)).to be(false)
    error = schema.validate_errors(invalid_doc).first
    expect(error[:message]).to include("missing required attribute")
    expect(error[:line]).to eq(1)
  end

  it "compiles a schema from a file" do
    ctx = Moxml.new(:leptris)
    skip "leptris binding has no RNG face" unless described_class.supported?(ctx)

    Tempfile.create(["schema", ".rng"]) do |file|
      file.write(RNG_SCHEMA)
      file.flush
      schema = ctx.relaxng_file(file.path)
      expect(schema.valid?(valid_doc)).to be(true)
      expect(schema.valid?(invalid_doc)).to be(false)
    end
  end

  it "raises a named NotImplementedError on engines without an RNG validator" do
    ctx = Moxml.new(:nokogiri)
    expect(described_class.supported?(ctx)).to be(false)
    expect { ctx.relaxng(RNG_SCHEMA) }
      .to raise_error(Moxml::NotImplementedError, /RELAX NG/)
  end

  it "names a malformed schema as a ValidationError" do
    ctx = Moxml.new(:leptris)
    skip "leptris binding has no RNG face" unless described_class.supported?(ctx)

    expect { ctx.relaxng("<not-a-schema/>") }
      .to raise_error(Moxml::ValidationError, /RELAX NG/)
  end
end
