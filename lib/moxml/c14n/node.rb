# frozen_string_literal: true

module Moxml
  module C14n
    # Base class for all C14N data-model nodes.
    # Ported from canon ( lutaml/canon ) — keeps the mature node-set
    # semantics needed for subset canonicalization (spec §3).
    class Node
      attr_reader :parent, :children

      def initialize
        @parent = nil
        @children = []
        @in_node_set = true
      end

      def add_child(child)
        child.parent = self
        @children << child
      end

      def in_node_set?
        @in_node_set
      end

      def in_node_set=(value)
        @in_node_set = value
      end

      # Return the text content of this node and all descendants.
      # ElementNode concatenates children's text_content; other nodes
      # (TextNode, CommentNode, etc.) return their value.
      def text_content
        children.map(&:text_content).join
      end

      protected

      attr_writer :parent
    end
  end
end
