require_relative "node"
require_relative "element"
require_relative "text"
require_relative "cdata"
require_relative "comment"
require_relative "processing_instruction"
require_relative "declaration"
require_relative "namespace"

module Moxml
  class Document < Node

    def add_declaration(version:, encoding:)
      @version = version
      @encoding = encoding
    end

    def root=(element)
      adapter.set_root(@native, element.native)
    end

    def root
      root_element = adapter.root(@native)
      root_element ? Element.wrap(root_element, context) : nil
    end

    def create_element(name)
      Element.new(adapter.create_element(name), context)
    end

    def create_text(content)
      Text.new(adapter.create_text(content), context)
    end

    def create_cdata(content)
      Cdata.new(adapter.create_cdata(content), context)
    end

    def create_comment(content)
      Comment.new(adapter.create_comment(content), context)
    end

    def create_processing_instruction(target, content)
      ProcessingInstruction.new(
        adapter.create_processing_instruction(target, content),
        context
      )
    end

    def create_declaration(version = "1.0", encoding = "UTF-8", standalone = nil)
      decl = adapter.create_declaration(version, encoding, standalone)
      Declaration.new(decl, context)
    end

    def add_child(node)
      node = prepare_node(node)

      if node.is_a?(Declaration)
        if children.empty?
          adapter.add_child(@native, node.native)
        else
          adapter.add_previous_sibling(children.first.native, node.native)
        end
      elsif root && !node.is_a?(ProcessingInstruction) && !node.is_a?(Comment)
        raise Error, "Document already has a root element"
      else
        adapter.add_child(@native, node.native)
      end
      self
    end

    def xpath(expression, namespaces = {})
      native_nodes = adapter.xpath(@native, expression, namespaces)
      native_nodes.map { |native_node| find_moxml_node(native_node) }
    end

    def at_xpath(expression, namespaces = {})
      if native_node = adapter.at_xpath(@native, expression, namespaces)
        find_moxml_node(native_node)
      end
    end

    private

    def find_moxml_node(native_node)
      @node_registry ||= {}
      @node_registry[native_node.object_id] || create_moxml_node(native_node)
    end

    def create_moxml_node(native_node)
      node = Node.wrap(native_node, context)
      @node_registry[native_node.object_id] = node
      node
    end
  end
end
