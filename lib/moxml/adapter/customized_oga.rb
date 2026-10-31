# frozen_string_literal: true

module Moxml
  module Adapter
    # Lifecycle record (#495): every override serves the :oga
    # adapter. The Opal surface that motivated them is deleted
    # (moxml#489 phase 4, 2026-10-31); the overrides remain because
    # the CRuby :oga adapter calls them on core paths, and the
    # adapter's fate -- the owner's removal decision, consumer
    # evidence in moxml#490 -- governs this file.
    module CustomizedOga
      autoload :EntityDecoderOverride, "moxml/adapter/customized_oga/entity_decoder"
      autoload :RawValueOverride, "moxml/adapter/customized_oga/raw_value_override"
      autoload :XmlDeclaration, "moxml/adapter/customized_oga/xml_declaration"
      autoload :XmlGenerator, "moxml/adapter/customized_oga/xml_generator"
    end
  end
end
