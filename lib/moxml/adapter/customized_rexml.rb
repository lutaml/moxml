# frozen_string_literal: true

module Moxml
  module Adapter
    # Lifecycle record (#495): engine-gap shims for the :rexml
    # adapter (Opal fallback; deleted with the Opal surface in
    # moxml#489 phase 4). No separate upstream ask; the adapter's
    # fate governs this file.
    module CustomizedRexml
      autoload :EntityReference,
               "moxml/adapter/customized_rexml/entity_reference"
      autoload :Formatter, "moxml/adapter/customized_rexml/formatter"
    end
  end
end
