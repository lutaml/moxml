# frozen_string_literal: true

require "spec_helper"
require "moxml/adapter/shared_examples/adapter_contract"

# The describe resolves the adapter constant at load time — under
# MRI nothing loads the Opal compat shim, so the whole describe must
# sit behind the engine check (the `if:` metadata alone still
# evaluates the constant reference).
if RUBY_ENGINE == "opal"
  RSpec.describe Moxml::Adapter::Oga do
    around do |example|
      Moxml.with_config(:oga, true, "UTF-8") do
        example.run
      end
    end

    it_behaves_like "xml adapter"
  end
end
