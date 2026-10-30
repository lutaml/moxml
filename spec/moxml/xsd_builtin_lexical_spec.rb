# frozen_string_literal: true

# Processing model §Validation (normative): pinned here.
#
# The rows are the conformance data (#496): spec/support/conformance_cases.rb
# is the single source — these examples iterate it, and
# `rake conformance:export` serializes the same rows for the moxml-rs and
# moxml-ts runners. Edit the data, not the examples.

require "spec_helper"

RSpec.describe Moxml::XSD do
  let(:ctx) { Moxml.new(:leptris) }

  def valid_lexical?(type, lexical)
    described_class.builtin_valid?(ctx, type, lexical)
  end

  describe ".builtin_valid?" do
    it "answers the facade-owned table identically without an engine" do
      expect(valid_lexical?("xs:integer", "3")).to be(true)
      expect do
        described_class.builtin_valid?(ctx, "xs:nope", "3")
      end.to raise_error(ArgumentError)
    end

    ConformanceCases::LEXICAL_CASES.each do |case_|
      it "[#{case_[:id]}] answers #{case_[:valid]} for #{case_[:type]} #{case_[:lexical].inspect}" do
        expect(valid_lexical?(case_[:type], case_[:lexical])).to eq(case_[:valid])
      end
    end

    # lutaml-xsd's engine context pins strict booleans on this face:
    # a grammar-invalid calendar lexical must answer false, never nil
    # (the with_date_fields short-circuit used to leak nil).
    it "answers a strict boolean for every supported name" do
      garbage = ["not-a-date", "", "   ", "12x", "9999-99-99Tzz"]

      Moxml::XSD::BuiltinLexical.names.each do |name|
        garbage.each do |lexical|
          answer = valid_lexical?(name, lexical)
          expect(answer.eql?(true) || answer.eql?(false)).to be(true),
                                                             "#{name} #{lexical.inspect} answered " \
                                                             "#{answer.inspect}, want a boolean"
        end
      end
    end
  end
end
