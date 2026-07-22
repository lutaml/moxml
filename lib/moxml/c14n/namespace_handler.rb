# frozen_string_literal: true

module Moxml
  module C14n
    # Namespace axis handler for inclusive C14N.
    # Implements W3C C14N 1.0 §2.3 / 1.1 §2.3 namespace rendering rules
    # for the document subset (full and partial).
    class NamespaceHandler
      attr_reader :encoder

      def initialize(encoder)
        @encoder = encoder
      end

      def process_namespaces(element, output, parent_element = nil)
        return unless element.in_node_set?

        namespaces = element.sorted_namespace_nodes.select(&:in_node_set?)

        if should_emit_empty_default_namespace?(element, namespaces, parent_element)
          output << ' xmlns=""'
        end

        namespaces.each do |ns|
          next if should_skip_namespace?(ns, parent_element)

          output << " "
          output << (ns.default_namespace? ? "xmlns" : "xmlns:#{ns.prefix}")
          output << '="'
          output << encoder.encode_attribute(ns.uri)
          output << '"'
        end
      end

      private

      # Emit xmlns="" if the element's nearest in-set ancestor had a non-empty
      # default namespace and this element does not.
      def should_emit_empty_default_namespace?(element, namespaces, parent_element)
        return false unless element.in_node_set?
        return false if namespaces.first&.default_namespace?
        return false unless parent_element

        parent_default_ns = parent_element.namespace_nodes.find do |ns|
          ns.default_namespace? && ns.in_node_set?
        end

        parent_default_ns && !parent_default_ns.uri.empty?
      end

      def should_skip_namespace?(namespace, parent_element)
        # The xml namespace is implicit, never rendered.
        return true if namespace.xml_namespace?
        # Skip namespaces already declared (with same URI) by an ancestor.
        return true if namespace_declared_by_ancestor?(namespace, parent_element)

        false
      end

      def namespace_declared_by_ancestor?(namespace, parent_element)
        return false unless parent_element

        parent_ns = parent_element.namespace_nodes.find do |candidate|
          candidate.prefix == namespace.prefix && candidate.in_node_set?
        end

        parent_ns && parent_ns.uri == ns.uri
      end
    end
  end
end
