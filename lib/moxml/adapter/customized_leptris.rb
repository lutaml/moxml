# frozen_string_literal: true

module Moxml
  module Adapter
    # Pure-Ruby node kinds that libleptris has no native representation
    # for: XML declarations, programmatic DOCTYPEs, and entity references.
    # The adapter stores them via NativeAttachment and serializes them
    # from #to_xml.
    module CustomizedLeptris
      autoload :Declaration, "moxml/adapter/customized_leptris/declaration"
      autoload :Doctype, "moxml/adapter/customized_leptris/doctype"
      autoload :EntityReference, "moxml/adapter/customized_leptris/entity_reference"
      autoload :TextSegment, "moxml/adapter/customized_leptris/text_segment"
    end
  end
end
