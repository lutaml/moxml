# frozen_string_literal: true

require_relative "node"

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML comment nodes
      class Comment < Node
        # Serialize as XML comment
        # LibXML auto-escapes content, we need to un-escape it
        def to_xml
          content = @native.content
            .gsub("&quot;", '"')
            .gsub("&apos;", "'")
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&amp;", "&")
          "<!--#{content}-->"
        end
      end
    end
  end
end
