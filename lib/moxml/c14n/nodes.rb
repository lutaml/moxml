# frozen_string_literal: true

module Moxml
  module C14n
    # C14N data-model node types. All nodes inherit from {Moxml::C14n::Node}.
    module Nodes
      autoload :AttributeNode, "moxml/c14n/nodes/attribute_node"
      autoload :CommentNode, "moxml/c14n/nodes/comment_node"
      autoload :ElementNode, "moxml/c14n/nodes/element_node"
      autoload :NamespaceNode, "moxml/c14n/nodes/namespace_node"
      autoload :ProcessingInstructionNode,
               "moxml/c14n/nodes/processing_instruction_node"
      autoload :RootNode, "moxml/c14n/nodes/root_node"
      autoload :TextNode, "moxml/c14n/nodes/text_node"
    end
  end
end
