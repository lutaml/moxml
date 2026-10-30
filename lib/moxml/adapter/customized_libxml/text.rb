# frozen_string_literal: true

# Lifecycle record: the :libxml adapter is deprecated (#491); this wrapper dies with it.

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

        # @native.to_s escapes & < > but leaves quotes alone, which text nodes need.
        def to_xml
          @native.to_s
        end
      end
    end
  end
end
