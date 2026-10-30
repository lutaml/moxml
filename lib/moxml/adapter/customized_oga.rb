# frozen_string_literal: true

module Moxml
  module Adapter
    # Lifecycle record (#495): every override serves the :oga adapter,
    # deprecated in moxml#491 and deleted with the Opal surface in
    # moxml#489 phase 4. No separate upstream ask -- the adapter's
    # fate governs this file.
    module CustomizedOga
      autoload :EntityDecoderOverride, "moxml/adapter/customized_oga/entity_decoder"
      autoload :RawValueOverride, "moxml/adapter/customized_oga/raw_value_override"
      autoload :XmlDeclaration, "moxml/adapter/customized_oga/xml_declaration"
      autoload :XmlGenerator, "moxml/adapter/customized_oga/xml_generator"
    end
  end
end
