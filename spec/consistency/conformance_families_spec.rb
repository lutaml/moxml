# frozen_string_literal: true

require "json"
require "tmpdir"
require "spec_helper"

# Conformance families 6 and 7 (#490 item 8):
#
# - c14n: canonical C14N 1.0 vectors (comments dropped). Every row
#   canonicalizes to IDENTICAL bytes on all adapters — the Ruby
#   reference and the leptris native delegation are pinned
#   byte-for-byte by the c14n suite.
# - xsd_structural: single-file schema + instance pairs, the
#   committed facade verdict, verified identical on both primary
#   engines through `Context#xsd_file`.
#
# Both export into conformance/moxml-conformance.json (schema 5) for
# the cross-language runners; a runner mismatch on any row is a REAL
# model finding — report it, don't bend the row.
RSpec.describe "conformance families: c14n and xsd_structural (schema 5)" do
  let(:primary) { %i[nokogiri leptris] }

  describe "c14n" do
    Moxml::C14nCases::CONFORMANCE_CASES.each do |id, input, canonical|
      it "canonicalizes #{id} to the committed bytes" do
        Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
          begin
            doc = Moxml.new(name).parse(input)
          rescue Moxml::Error, NotImplementedError, LoadError
            next
          end

          expect(Moxml::C14n.canonicalize(doc)).to eq(canonical)
        end
      end
    end

    it "is exported by the dataset with the committed rows" do
      path = File.expand_path("../../conformance/moxml-conformance.json",
                              __dir__)
      family = JSON.parse(File.read(path)).dig("cases", "c14n") || []
      expect(family.map { |row| row["id"] })
        .to eq(Moxml::C14nCases::CONFORMANCE_CASES.map(&:first))
    end
  end

  describe "xsd_structural" do
    Moxml::XsdStructuralCases::CONFORMANCE_CASES.each do |id, schema, instance, valid|
      it "answers #{id} as #{valid ? 'valid' : 'invalid'} on both primaries" do
        Dir.mktmpdir do |dir|
          schema_path = File.join(dir, "#{id}.xsd")
          File.write(schema_path, schema)
          primary.each do |name|
            ctx = Moxml.new(name)
            errors = ctx.xsd_file(schema_path).validate(ctx.parse(instance))
            expect(errors.empty?).to be(valid),
                                     "#{id} on #{name}: #{errors.map(&:message).join('; ')}"
          end
        end
      end
    end

    it "is exported by the dataset with the committed rows" do
      path = File.expand_path("../../conformance/moxml-conformance.json",
                              __dir__)
      family = JSON.parse(File.read(path)).dig("cases", "xsd_structural") || []
      expect(family.map { |row| row["id"] })
        .to eq(Moxml::XsdStructuralCases::CONFORMANCE_CASES.map(&:first))
    end
  end
end
