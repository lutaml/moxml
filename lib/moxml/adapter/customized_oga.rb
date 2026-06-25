# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedOga
      autoload :EntityDecoderOverride, "moxml/adapter/customized_oga/entity_decoder"
      autoload :RawValueOverride, "moxml/adapter/customized_oga/raw_value_override"
      autoload :XmlDeclaration, "moxml/adapter/customized_oga/xml_declaration"
      autoload :XmlGenerator, "moxml/adapter/customized_oga/xml_generator"
    end
  end
end
