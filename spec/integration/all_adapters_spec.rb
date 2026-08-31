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
    "Moxml::Parse Behavior",
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

      all_shared_examples.each do |shared_example_name|
        # The performance battery runs only under RUN_PERFORMANCE /
        # `rake spec:performance` (issue #45) - tagged at inclusion:
        # definition-site metadata on the shared group does not
        # propagate through this indirection.
        if shared_example_name == "Performance Examples"
          it_behaves_like shared_example_name, performance: true
        else
          it_behaves_like shared_example_name
        end
      end
    end
  end
end
