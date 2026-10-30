# frozen_string_literal: true

module Moxml
  module Adapter
    # Pure-Ruby node kinds that libleptris has no native representation
    # for: XML declarations, programmatic DOCTYPEs, entity references,
    # and document-level processing instructions.
    # The adapter stores them via NativeAttachment and serializes them
    # from #to_xml.
    #
    # Lifecycle record (#495): a tracked shim, not an adapter-fate
    # case — the parse-time entity-retention gap is the last engine
    # ask of the #275 mutation-completion round; when the engine ships
    # native retention these classes dissolve into Base.
    module CustomizedLeptris
      autoload :Declaration, "moxml/adapter/customized_leptris/declaration"
      autoload :Doctype, "moxml/adapter/customized_leptris/doctype"
      autoload :EntityReference, "moxml/adapter/customized_leptris/entity_reference"
      autoload :TextSegment, "moxml/adapter/customized_leptris/text_segment"
    end
  end
end
