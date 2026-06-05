# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML comment nodes
      class Comment < Node
        # libxml stores comment payload verbatim.
        def to_xml
          "<!--#{@native.content}-->"
        end
      end
    end
  end
end
