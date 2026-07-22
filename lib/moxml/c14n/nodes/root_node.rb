# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Root node representing the document root.
      class RootNode < Node
        def name
          "#document"
        end

        def node_type
          :root
        end

        def children=(new_children)
          @children = new_children
        end
      end
    end
  end
end
