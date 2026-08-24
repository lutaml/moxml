# frozen_string_literal: true

# Leptris needs the unreleased programmatic-document-construction C
# API; skip its integration matrix until the binding ships it.
#
# const_defined? only — deliberately NO require here: loading a native
# gem at example-group definition time is a load-order side effect
# (and the only new load-time behavior on this branch). The leptris
# adapter spec is what loads the gem in its own process.
def leptris_ready?
  return false unless Object.const_defined?(:Leptris)

  Leptris::XML::Document.respond_to?(:create)
end

# Leptris known gaps: shared-example groups that do not pass yet, each
# with its reason. Groups not listed here run fully. This manifest is
# the burn-down checklist for the adapter — remove entries as they
# close. Verified against leptris 1.7.0 (fixed #518, #519, #525, #526,
# #534 — Comment and ProcessingInstruction groups left the list;
# Moxml Integration remains for leptris#540).
LEPTRIS_KNOWN_GAPS = {
  "Moxml::Cdata" => "adapter: CDATA serialization formatting",
  "Moxml::Declaration" => "adapter: declaration serialization formatting",
  "Moxml::Doctype" => "adapter: doctype wrapper serialization formatting",
  "Moxml::EntityReference" => "adapter: entity-reference pipeline not wired",
  "Entity Reference Whitespace Preservation" => "adapter: entity-reference pipeline not wired",
  "Moxml::Attribute" => "adapter: attribute rename and namespace mutation (leptris binding lacks per-attribute namespace accessors)",
  "Attribute Examples" => "adapter: attribute serialization edge cases",
  "Moxml::Element" => "adapter: mixed content and namespace setter",
  "Namespace Examples" => "adapter: namespace inheritance overrides",
  "Moxml::Namespace" => "adapter: namespace inheritance overrides",
  "Moxml::Node" => "adapter: parent resolution edge case",
  "Moxml::Text" => "adapter: text entity encoding",
  "Moxml Integration" => "leptris#540: insert_before rejects detached elements on rootless documents (bottom-up construction)",
  "Moxml Edge Cases" => "adapter: deep nesting / CDATA markers / default-namespace changes",
  "Moxml Line Ending" => "adapter: CRLF re-serialization stability",
  "Basic Usage Examples" => "adapter: document-creation workflows",
  "README Examples" => "adapter: builder + thread-safety workflows",
  "XPath Examples" => "adapter: attribute-node XPath results",
}.freeze

RSpec.describe "Cross-adapter integration" do
  # Integration shared examples - use the names as defined in the files
  all_shared_examples = [
    "Moxml::Node",
    "Moxml::Namespace",
    "Moxml::Attribute",
    "Moxml::NodeSet",
    "Moxml::Element",
    "Moxml::Cdata",
    "Moxml::Comment",
    "Moxml::Text",
    "Moxml::ProcessingInstruction",
    "Moxml::Declaration",
    "Moxml::Doctype",
    "Moxml::Document",
    "Moxml::EntityReference",
    "Moxml::Context",
    "Moxml::Builder",
    "Moxml::DocumentBuilder",
    "Moxml Integration",
    "Moxml Edge Cases",
    "Attribute Examples",
    "Basic Usage Examples",
    "Namespace Examples",
    "README Examples",
    "XPath Examples",
    "Memory Usage Examples",
    "Thread Safety Examples",
    "Entity Reference Whitespace Preservation",
    "Moxml Line Ending",
    "Performance Examples",
  ]

  Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
    context "with #{adapter_name}" do
      around do |example|
        Moxml.with_config(adapter_name) do
          example.run
        end
      end

      if adapter_name == :leptris && !leptris_ready?
        before { skip "requires leptris with Leptris::XML::Document.create (unreleased C API)" }
      end

      gaps = adapter_name == :leptris && leptris_ready? ? LEPTRIS_KNOWN_GAPS : {}
      (all_shared_examples - gaps.keys).each do |shared_example_name|
        it_behaves_like shared_example_name
      end

      gaps.each do |gap_name, reason|
        describe gap_name do
          before { skip "leptris known gap: #{reason}" }

          it_behaves_like gap_name
        end
      end
    end
  end
end
