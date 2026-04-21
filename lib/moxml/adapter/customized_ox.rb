# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedOx
      autoload :Attribute, "moxml/adapter/customized_ox/attribute"
      autoload :EntityReference, "moxml/adapter/customized_ox/entity_reference"
      autoload :Namespace, "moxml/adapter/customized_ox/namespace"
      autoload :Text, "moxml/adapter/customized_ox/text"
    end
  end
end
