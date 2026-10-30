# frozen_string_literal: true

# Processing model §Validation (normative): pinned here.

require "spec_helper"

# The regex-translator conformance dataset (#496): the translator's
# answers AS DATA — translatable-or-not, and what the translated
# regex does to sample values — pinned by the Ruby suite and exported
# for the Rust/TS runners. A row failing here breaks the
# cross-language contract.
RSpec.describe "XSD-regex translator conformance dataset" do
  let(:translator) { Moxml::XSD::SchemaRules::XsdRegex }

  it "carries the dataset" do
    expect(translator::CONFORMANCE_CASES.size).to be >= 20
  end

  it "answers every row exactly as the dataset expects" do
    translator::CONFORMANCE_CASES.each do |pattern, value, matches, translatable|
      regex = translator.translate(pattern)
      if translatable
        expect(regex).not_to be_nil,
                             "#{pattern.inspect}: dataset says translatable, got nil"
        answer = regex.match?(value)
        expect(answer).to eql(matches),
                          "#{pattern.inspect} on #{value.inspect}: got " \
                          "#{answer.inspect}, dataset expects #{matches.inspect}"
      else
        expect(regex).to be_nil,
                         "#{pattern.inspect}: dataset says NOT translatable, " \
                         "got #{regex.inspect}"
      end
    end
  end
end
