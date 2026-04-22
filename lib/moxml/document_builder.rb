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

      # Transfer has_declaration flag if present in attachments
      if adapter.respond_to?(:attachments) &&
          adapter.attachments.key?(native_doc, :has_declaration)
        has_declaration = adapter.attachments.get(native_doc, :has_declaration)
        @current_doc.has_xml_declaration = has_declaration
      end

      # Transfer DOCTYPE from parsed document if it exists in attachments
      if adapter.respond_to?(:attachments) &&
          adapter.attachments.key?(native_doc, :doctype)
        doctype = adapter.attachments.get(native_doc, :doctype)
        if doctype
          adapter.attachments.set(@current_doc.native, :doctype, doctype)
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
      content = adapter.text_content(node)

      # Check if we should restore entity references for this text
      if context.config.restore_entities && text_has_restorable_entities?(content)
        restore_entities_in_text(content)
      else
        @node_stack.last&.add_child(Text.new(prepared, context))
      end
    end

    def text_has_restorable_entities?(content)
      return false unless content

      registry = context.entity_registry
      codepoints = registry.restorable_codepoints
      content.each_char do |char|
        return true if codepoints.include?(char.ord)
      end
      false
    end

    def restore_entities_in_text(content)
      parent = @node_stack.last
      return unless parent

      registry = context.entity_registry
      config = context.config
      buffer = +""

      content.to_s.each_char do |char|
        codepoint = char.ord
        name = registry.primary_name_for_codepoint(codepoint)

        if name && registry.should_restore?(codepoint, config: config)
          # Flush buffered text before the entity
          unless buffer.empty?
            parent.add_child(Text.new(adapter.create_text(buffer), context))
            buffer.clear
          end
          parent.add_child(
            EntityReference.new(adapter.create_entity_reference(name), context),
          )
        else
          buffer << char
        end
      end

      # Flush remaining buffer
      unless buffer.empty?
        parent.add_child(Text.new(adapter.create_text(buffer), context))
      end
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

    def visit_entity_reference(node)
      prepared = adapter.prepare_for_new_document(node, @current_doc.native)
      @node_stack.last&.add_child(EntityReference.new(prepared, context))
    end

    def visit_children(node)
      children(node).each { |child| visit_node(child) }
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
