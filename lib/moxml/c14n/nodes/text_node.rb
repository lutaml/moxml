# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Text node. Stores the decoded value (entity refs resolved).
      class TextNode < Node
        attr_accessor :value

        def initialize(value:)
          super()
          @value = value
        end

        def name
          "#text"
        end

        def node_type
          :text
        end

        def text_content
          @value
        end
      end
    end
  end
end
