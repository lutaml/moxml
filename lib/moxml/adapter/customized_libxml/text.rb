# frozen_string_literal: true

require_relative "node"

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

        # Serialize as XML with proper escaping
        # LibXML's .content already contains escaped text, but it over-escapes
        # quotes which don't need escaping in text nodes (only in attributes)
        def to_xml
          @native.content.gsub("&quot;", '"')
        end
      end
    end
  end
end
