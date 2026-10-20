# frozen_string_literal: true

module Moxml
  module C14n
    # C14N 1.0/1.1 processor. Walks the data model and emits canonical
    # octets. Handles node-set subsets (omitted ancestors), xml:base
    # fixup, and xml:* inheritable attribute resolution.
    #
    # Ported from canon (lutaml/canon).
    class Processor
      attr_reader :with_comments

      def initialize(with_comments: false)
        @with_comments = with_comments
        @encoder = CharacterEncoder.new
        @namespace_handler = NamespaceHandler.new(@encoder)
        @attribute_handler = AttributeHandler.new(@encoder)
        @xml_base_handler = XmlBaseHandler.new
      end

      def process(root_node)
        output = (+"")
        process_node(root_node, output)
        # Document-level PI/comment rendering uses a newline as a
        # SEPARATOR between nodes (and around the root), not as a
        # leading/trailing pad: the canonical form starts and ends
        # with the first/last node itself (libxml2 oracle).
        output.chomp! if root_node.node_type == :root
        output
      end

      private

      def process_node(node, output, parent_element = nil, omitted_ancestors = [])
        case node.node_type
        when :root
          node.children.each { |child| process_node(child, output) }
        when :element
          process_element_node(node, output, parent_element, omitted_ancestors)
        when :text
          process_text_node(node, output)
        when :comment
          process_comment_node(node, output, parent_element)
        when :processing_instruction
          process_pi_node(node, output, parent_element)
        end
      end

      def process_element_node(node, output, parent_element, omitted_ancestors)
        if node.in_node_set?
          render_element(node, output, parent_element, omitted_ancestors)
        else
          # Element not in node-set, but its children may be. Pass the
          # element as an omitted ancestor for inheritable-attr fixup.
          new_omitted = omitted_ancestors + [node]
          node.children.each do |child|
            process_node(child, output, parent_element, new_omitted)
          end
        end
      end

      def render_element(node, output, parent_element, omitted_ancestors)
        output << "<" << node.qname

        @namespace_handler.process_namespaces(node, output, parent_element)
        process_element_attributes(node, output, omitted_ancestors)

        output << ">"

        node.children.each { |child| process_node(child, output, node, []) }

        output << "</" << node.qname << ">"
      end

      def process_element_attributes(node, output, omitted_ancestors)
        @attribute_handler.process_attributes(node, output, omitted_ancestors)

        return unless omitted_ancestors.any?

        fixed_base = @xml_base_handler.fixup_xml_base(node, omitted_ancestors)
        return unless fixed_base && !fixed_base.empty?

        has_base = node.attribute_nodes.any?(&:xml_base?)
        return if has_base

        output << ' xml:base="'
        output << @encoder.encode_attribute(fixed_base)
        output << '"'
      end

      def process_text_node(node, output)
        return unless node.in_node_set?

        output << @encoder.encode_text(node.value)
      end

      def process_comment_node(node, output, parent_element)
        return unless with_comments
        return unless node.in_node_set?

        ensure_separator(output) if parent_element.nil?
        output << "<!--" << node.value << "-->"
        output << "\n" if parent_element.nil?
      end

      def process_pi_node(node, output, parent_element)
        return unless node.in_node_set?
        # C14N never emits the XML declaration; the "xml" target is
        # reserved and cannot appear as a PI in a well-formed document.
        return if node.target.to_s.casecmp("xml").zero?

        ensure_separator(output) if parent_element.nil?
        output << "<?" << node.target
        output << " " << node.data unless node.data.to_s.empty?
        output << "?>"
        output << "\n" if parent_element.nil?
      end

      # One newline between document-level nodes, never a doubled
      # separator (a PI's trailing newline already starts the next
      # node's line).
      def ensure_separator(output)
        output << "\n" if output.length.positive? && !output.end_with?("\n")
      end
    end
  end
end
