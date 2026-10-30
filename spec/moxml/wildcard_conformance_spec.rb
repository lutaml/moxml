# frozen_string_literal: true

# Processing model §Validation (normative): pinned here.

require "spec_helper"

# The wildcard-face conformance dataset (#496): admission (covers?)
# and negative-exclusion answers AS DATA, pinned by the Ruby suite
# and exported for the Rust/TS runners. A row failing here breaks the
# cross-language contract. Rows drive the real Wildcard through its
# public constructor — disallowed entries in their pre-resolution
# token form, item qnames in the Clark form the face receives.
RSpec.describe "wildcard-face conformance dataset" do
  it "carries the dataset" do
    expect(Moxml::XSD::SchemaRules::Wildcard::WILDCARD_CASES.size).to be >= 20
  end

  it "answers every row exactly as the dataset expects" do
    Moxml::XSD::SchemaRules::Wildcard::WILDCARD_CASES.each do |row|
      constraint, process, not_namespace, not_qname, item_ns, item_qname,
        defined, sibling_names, covers, exclusion = row
      wildcard = Moxml::XSD::SchemaRules::Wildcard.new(
        constraint, process,
        not_namespace: not_namespace, not_qname: not_qname.join(" "),
        element: nil
      )

      covers_answer = wildcard.covers?(item_ns.to_sym)
      expect(covers_answer).to eql(covers),
                               "covers?(#{item_ns.inspect}) under " \
                               "#{constraint.inspect}: got " \
                               "#{covers_answer.inspect}, dataset expects " \
                               "#{covers.inspect}"

      exclusion_answer = wildcard.negative_exclusion(
        item_qname, item_ns.to_sym,
        defined: defined, sibling_names: sibling_names
      )
      expected_exclusion = exclusion&.to_sym
      expect(exclusion_answer).to eql(expected_exclusion),
                                  "negative_exclusion(#{item_qname.inspect}, " \
                                  "#{item_ns.inspect}) under " \
                                  "#{constraint.inspect}: got " \
                                  "#{exclusion_answer.inspect}, dataset expects " \
                                  "#{expected_exclusion.inspect}"
    end
  end
end
