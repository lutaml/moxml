# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Comment node.
      class CommentNode < Node
        attr_reader :value

        def initialize(value:)
          super()
          @value = value
        end

        def name
          "comment"
        end

        def node_type
          :comment
        end

        def text_content
          @value
        end
      end
    end
  end
end
