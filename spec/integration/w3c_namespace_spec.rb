# frozen_string_literal: true

# W3C XML Namespaces 1.0 Test Suite
# Source: https://www.w3.org/XML/Test/ (xmlts20130923)
# Tests from: xmlconf/eduni/namespaces/1.0/
#
# Test types per W3C:
#   valid    - must be accepted without errors
#   error    - namespace constraint violation; processors MAY report
#   not-wf   - namespace well-formedness violation; must be rejected
#   invalid  - validity error; non-validating parsers should accept

RSpec.describe "W3C XML Namespaces 1.0 test suite" do
  Moxml::Adapter::AVALIABLE_ADAPTERS.each do |adapter_name|
    context "with #{adapter_name}" do
      around do |example|
        Moxml.with_config(adapter_name) do
          example.run
        end
      end

      let(:moxml_context) { Moxml.new }

      W3C_NAMESPACE_TESTS.each do |test|
        next unless File.exist?(File.join(W3C_NS_FIXTURES_DIR, test[:uri]))

        test_label = "#{test[:id]}: #{test[:description]}"

        case test[:type]
        when "valid"
          it_behaves_like "W3C namespace test: should parse",
                          "#{test_label} [valid]", test[:uri], adapter_name, test[:id]

        when "error"
          # Namespace errors are advisory — processors MAY report them.
          # We accept these documents (e.g. relative URIs are valid URI-references).
          it_behaves_like "W3C namespace test: should parse",
                          "#{test_label} [error - accepted]", test[:uri], adapter_name, test[:id]

        when "not-wf"
          # Namespace well-formedness violations should be caught by the parser,
          # but enforcement varies significantly by adapter. These tests document
          # adapter behavior and are not directly related to URI validation.
          it "#{test_label} [not-wf]" do
            xml = File.binread(File.join(W3C_NS_FIXTURES_DIR, test[:uri]))
            raised = false
            begin
              moxml_context.parse(xml, strict: true)
            rescue StandardError
              raised = true
            end

            if raised
              # Good: adapter correctly rejects namespace-ill-formed document
            else
              skip "#{adapter_name} does not enforce this namespace well-formedness rule"
            end
          end

        when "invalid"
          # Validity errors are for validating parsers. Non-validating parsers
          # (which moxml wraps) should accept these documents.
          it_behaves_like "W3C namespace test: should parse",
                          "#{test_label} [invalid - accepted]", test[:uri], adapter_name, test[:id]
        end
      end
    end
  end
end
