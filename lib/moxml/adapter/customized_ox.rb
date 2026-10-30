# frozen_string_literal: true

module Moxml
  module Adapter
    # Lifecycle record (#495): engine-gap shims for the :ox adapter,
    # deprecated in moxml#491 -- removed with it after the cycle.
    # No separate upstream ask; the adapter's fate governs.
    module CustomizedOx
      autoload :Attribute, "moxml/adapter/customized_ox/attribute"
      autoload :EntityReference, "moxml/adapter/customized_ox/entity_reference"
      autoload :Namespace, "moxml/adapter/customized_ox/namespace"
      autoload :Text, "moxml/adapter/customized_ox/text"
    end
  end
end
