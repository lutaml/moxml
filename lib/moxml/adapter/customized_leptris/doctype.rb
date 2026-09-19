# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # Wrapper for a programmatic DOCTYPE. libleptris can create
      # one (Document#set_doctype, 1.9.176 / #212) but cannot unset
      # it, and the facade contract makes DOCTYPEs removable nodes —
      # so Moxml keeps this value object as the lifecycle record in
      # the document's attachments.
      class Doctype
        attr_accessor :name, :external_id, :system_id, :parent_doc

        def initialize(name, external_id = nil, system_id = nil)
          @name = name
          @external_id = external_id
          @system_id = system_id
        end

        def to_xml
          XmlEmitter.doctype_xml(name, external_id, system_id)
        end

        def ==(other)
          other.is_a?(self.class) &&
            name == other.name &&
            external_id == other.external_id &&
            system_id == other.system_id
        end
      end
    end
  end
end
