# frozen_string_literal: true

# Processing model §Validation (normative): pinned here.

require "spec_helper"

# The conformance dataset is the model's builtin-lexical answers AS
# DATA (#496): the Ruby suite pins every row here, and the exported
# JSON (rake conformance:export) is what moxml-rs and moxml-ts run.
# A row that fails here breaks the cross-language contract, not just
# this implementation.
RSpec.describe "builtin lexical conformance dataset" do
  def valid_lexical?(type, lexical)
    Moxml::XSD.builtin_valid?(Moxml.new(:leptris), type, lexical)
  end

  it "carries the dataset" do
    expect(Moxml::XSD::BuiltinLexical::CONFORMANCE_CASES.size).to be >= 80
  end

  it "answers every row exactly as the dataset expects" do
    Moxml::XSD::BuiltinLexical::CONFORMANCE_CASES.each do |type, lexical, expected|
      answer = valid_lexical?(type, lexical)
      expect(answer).to eql(expected),
                        "#{type} #{lexical.inspect}: got #{answer.inspect}, " \
                        "dataset expects #{expected.inspect}"
    end
  end

  it "keeps every dataset type in the table" do
    Moxml::XSD::BuiltinLexical::CONFORMANCE_CASES.each do |type, _lexical, _expected|
      expect do
        valid_lexical?(type, "")
      end.not_to raise_error
    end
  end
end
