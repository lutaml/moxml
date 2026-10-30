# frozen_string_literal: true

# Lifecycle record: the :libxml adapter is deprecated (#491); this wrapper dies with it.

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
