# lib/moxml/document_builder.rb
module Moxml
  class DocumentBuilder
    attr_reader :context

    def initialize(context)
      @context = context
      @node_stack = []
    end

    def build(native_doc)
      @current_doc = context.create_document
      visit_node(native_doc)
      @current_doc
    end

    private

    def visit_node(node)
      node_name = node.respond_to?(:name) ? node.name : node
      method_name = "visit_#{node_type(node)}"
      if respond_to?(method_name, true)
        send(method_name, node)
      end
    end

    def visit_document(doc)
      @node_stack.push(@current_doc)
      visit_children(doc)
      @node_stack.pop
    end

    def visit_element(node)
      element = Element.new(node, context)
      if @node_stack.empty?
        # For root element, we need to set it directly
        adapter.set_root(@current_doc.native, element.native)
      else
        @node_stack.last.add_child(element)
      end
      @node_stack.push(element)
      visit_children(node)
      @node_stack.pop
      element
    end

    def visit_text(node)
      @node_stack.last.add_child(Text.new(node, context)) if @node_stack.any?
    end

    def visit_cdata(node)
      @node_stack.last.add_child(Cdata.new(node, context)) if @node_stack.any?
    end

    def visit_comment(node)
      @node_stack.last.add_child(Comment.new(node, context)) if @node_stack.any?
    end

    def visit_processing_instruction(node)
      @node_stack.last.add_child(ProcessingInstruction.new(node, context)) if @node_stack.any?
    end

    def visit_children(node)
      node_children = children(node).dup
      node_children.each_with_index do |child, index|
        visit_node(child)
      end
    end

    def node_type(node)
      context.config.adapter.node_type(node)
    end

    def children(node)
      context.config.adapter.children(node)
    end

    def adapter
      context.config.adapter
    end
  end
end
