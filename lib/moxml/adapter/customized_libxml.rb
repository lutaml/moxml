# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      autoload :Cdata, "moxml/adapter/customized_libxml/cdata"
      autoload :Comment, "moxml/adapter/customized_libxml/comment"
      autoload :Declaration, "moxml/adapter/customized_libxml/declaration"
      autoload :Element, "moxml/adapter/customized_libxml/element"
      autoload :EntityReference,
               "moxml/adapter/customized_libxml/entity_reference"
      autoload :Node, "moxml/adapter/customized_libxml/node"
      autoload :ProcessingInstruction,
               "moxml/adapter/customized_libxml/processing_instruction"
      autoload :Text, "moxml/adapter/customized_libxml/text"
    end
  end
end
