# frozen_string_literal: true

require_relative "node"

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML CDATA section nodes
      class Cdata < Node
        # Serialize as XML CDATA section
        # LibXML auto-escapes content, we need to un-escape it
        def to_xml
          content = @native.content
            .gsub("&quot;", '"')
            .gsub("&apos;", "'")
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&amp;", "&")

          # Handle CDATA end marker escaping (]]> becomes ]]]]><![CDATA[>)
          # Replace all ]]> markers in the content before wrapping
          escaped_content = content.gsub("]]>", "]]]]><![CDATA[>")
          "<![CDATA[#{escaped_content}]]>"
        end
      end
    end
  end
end
