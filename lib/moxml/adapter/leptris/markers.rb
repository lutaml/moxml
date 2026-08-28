# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      module Markers
        # Marker presence is a document-level fact: parse records it,
        # the ER builder path flips it, and the split/restore scans
        # consult it. Customized natives only exist as split products
        # of marker-bearing text, so they always report true.
        def entity_bearing?(native)
          case native
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
             CustomizedLeptris::EntityReference, CustomizedLeptris::TextSegment,
             CustomizedLeptris::DocumentPI
            true
          else
            doc = native.document
            doc.nil? || attachments.get(doc, :entity_markers) != false
          end
        end

        # Expand marker-bearing text nodes into the child sequence the
        # moxml contract exposes: text, EntityReference, text, ...
        def split_entity_markers(natives, parent)
          result = []
          natives.each do |child|
            # FFI Text#content returns a fresh unfrozen BINARY string:
            # retag in place (dup would be a throwaway allocation), but
            # before include? — BINARY.include? with the UTF-8 marker raises
            if child.is_a?(::Leptris::XML::Text)
              content = child.content
              content.force_encoding("UTF-8")
            end
            if content&.include?(Entity::MARKER)
              content.scan(/([^#{Entity::MARKER}]*)(?:#{Entity::MARKER}([\w.:-]+);)?/o) do
                text_part = Regexp.last_match(1)
                name = Regexp.last_match(2)
                result << CustomizedLeptris::TextSegment.new(text_part, parent) unless text_part.empty?
                result << CustomizedLeptris::EntityReference.new(name) if name
              end
            else
              result << child
            end
          end
          result
        end
      end
    end
  end
end
