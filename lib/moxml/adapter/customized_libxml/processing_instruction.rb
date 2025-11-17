# frozen_string_literal: true

require_relative "node"

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML processing instruction nodes
      class ProcessingInstruction < Node
        # Serialize as XML processing instruction
        # LibXML auto-escapes content, we need to un-escape it
        def to_xml
          target = @native.name
          content = @native.content

          # Un-escape LibXML's automatic escaping
          if content && !content.empty?
            unescaped = content.gsub("&quot;", '"')
                               .gsub("&apos;", "'")
                               .gsub("&lt;", "<")
                               .gsub("&gt;", ">")
                               .gsub("&amp;", "&")
            "<?#{target} #{unescaped}?>"
          else
            "<?#{target}?>"
          end
        end
      end
    end
  end
end
