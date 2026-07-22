# frozen_string_literal: true

module Moxml
  module C14n
    # Attribute axis handler for inclusive C14N.
    # Implements W3C C14N 1.0 §2.4 / 1.1 §2.4 attribute rendering,
    # including resolution of simple inheritable attributes (xml:lang,
    # xml:space) for document subsets.
    class AttributeHandler
      attr_reader :encoder

      def initialize(encoder)
        @encoder = encoder
      end

      def process_attributes(element, output, omitted_ancestors = [])
        return unless element.in_node_set?

        attributes = collect_attributes(element, omitted_ancestors)
        attributes.each do |attr|
          output << " "
          output << attr.qname
          output << '="'
          output << encoder.encode_attribute(attr.value)
          output << '"'
        end
      end

      private

      def collect_attributes(element, omitted_ancestors)
        attributes = element.sorted_attribute_nodes.select(&:in_node_set?)

        return attributes if omitted_ancestors.empty?

        inherited = collect_inherited_attributes(element, omitted_ancestors)
        merge_attributes(attributes, inherited)
      end

      # Walk omitted ancestors to collect simple inheritable attributes
      # not already declared on the element. Per C14N 1.1 §2.4, these
      # are inherited from the nearest ancestor in which they are declared.
      def collect_inherited_attributes(element, omitted_ancestors)
        inherited = []
        seen = Set.new

        element.attribute_nodes.each do |attr|
          seen.add(attr.name) if attr.simple_inheritable?
        end

        omitted_ancestors.reverse_each do |ancestor|
          ancestor.attribute_nodes.each do |attr|
            next unless attr.simple_inheritable?
            next if seen.include?(attr.name)

            inherited << attr
            seen.add(attr.name)
          end
        end

        inherited
      end

      def merge_attributes(element_attrs, inherited_attrs)
        (element_attrs + inherited_attrs).sort_by do |attr|
          [attr.namespace_uri.to_s, attr.local_name]
        end
      end
    end
  end
end
