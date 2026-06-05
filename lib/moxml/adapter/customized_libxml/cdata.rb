# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML CDATA section nodes
      class Cdata < Node
        # libxml stores CDATA payload verbatim. Only the `]]>` end-marker
        # needs splitting before re-wrapping.
        def to_xml
          escaped_content = @native.content.gsub("]]>", "]]]]><![CDATA[>")
          "<![CDATA[#{escaped_content}]]>"
        end
      end
    end
  end
end
