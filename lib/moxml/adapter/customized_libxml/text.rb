# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML text nodes
      class Text < Node
        def to_s
          @native.content
        end

        def text
          @native.content
        end

        # Serialize as XML with proper escaping. The previous implementation
        # used #content (which is the *decoded* text) and lost the escape
        # of "&" → "&amp;". libxml's native #to_s on a text node correctly
        # escapes "&", "<", and ">", leaving quotes alone (quotes only need
        # escaping inside attribute values, not text content).
        def to_xml
          @native.to_s
        end
      end
    end
  end
end
