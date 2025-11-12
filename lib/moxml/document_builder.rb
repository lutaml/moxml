# frozen_string_literal: true

module Moxml
  class DocumentBuilder
    attr_reader :context

    def initialize(context)
      @context = context
      @node_stack = []
    end

    def build(native_doc)
      @current_doc = context.create_document(native_doc)

      # Transfer DOCTYPE from parsed document if it exists
      if native_doc.respond_to?(:instance_variable_get) &&
          native_doc.instance_variable_defined?(:@moxml_doctype)
        doctype = native_doc.instance_variable_get(:@moxml_doctype)
        if doctype
          @current_doc.native.instance_variable_set(:@moxml_doctype,
                                                    doctype)
        end
      end

      visit_node(native_doc)
      @current_doc
    end

    private

    def visit_node(node)
      method_name = "visit_#{node_type(node)}"
      return unless respond_to?(method_name, true)

      send(method_name, node)
    end

    def visit_document(doc)
      @node_stack.push(@current_doc)
      visit_children(doc)
      @node_stack.clear
    end

    def visit_element(node)
      childless_node = adapter.duplicate_node(node)
      adapter.replace_children(childless_node, [])
      # Prepare node for new document (LibXML needs this)
      childless_node = adapter.prepare_for_new_document(
        childless_node,
        @current_doc.native,
      )
      element = Element.new(childless_node, context)
      @node_stack.last.add_child(element)

      @node_stack.push(element) # add a parent for its children
      visit_children(node)
      @node_stack.pop # remove the parent
    end

    def visit_text(node)
      # Prepare node for new document before wrapping
      prepared = adapter.prepare_for_new_document(node, @current_doc.native)
      @node_stack.last&.add_child(Text.new(prepared, context))
    end

    def visit_cdata(node)
      prepared = adapter.prepare_for_new_document(node, @current_doc.native)
      @node_stack.last&.add_child(Cdata.new(prepared, context))
    end

    def visit_comment(node)
      prepared = adapter.prepare_for_new_document(node, @current_doc.native)
      @node_stack.last&.add_child(Comment.new(prepared, context))
    end

    def visit_processing_instruction(node)
      prepared = adapter.prepare_for_new_document(node, @current_doc.native)
      @node_stack.last&.add_child(ProcessingInstruction.new(prepared, context))
    end

    def visit_doctype(node)
      prepared = adapter.prepare_for_new_document(node, @current_doc.native)
      @node_stack.last&.add_child(Doctype.new(prepared, context))
    end

    def visit_children(node)
      node_children = children(node).dup
      node_children.each do |child|
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
