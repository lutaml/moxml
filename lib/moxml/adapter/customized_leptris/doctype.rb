# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # Wrapper for a programmatic DOCTYPE. libleptris only parses
      # DOCTYPEs from source; it has no API to create one, so Moxml
      # stores this value object in the document's attachments.
      class Doctype
        attr_accessor :name, :external_id, :system_id, :parent_doc

        def initialize(name, external_id = nil, system_id = nil)
          @name = name
          @external_id = external_id
          @system_id = system_id
        end

        def to_xml
          output = "<!DOCTYPE #{name}"
          if external_id && !external_id.to_s.empty?
            output += %( PUBLIC "#{external_id}")
            output += %( "#{system_id}") if system_id
          elsif system_id && !system_id.to_s.empty?
            output += %( SYSTEM "#{system_id}")
          end
          "#{output}>"
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
