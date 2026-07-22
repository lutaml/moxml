# frozen_string_literal: true

module Moxml
  module C14n
    # Builds a C14N data model from a Moxml::Node tree (or XML string).
    #
    # The data model exists because canonicalization needs:
    #   - sorted namespace and attribute axes (spec §2.3, §2.4)
    #   - in_node_set flags for subset canonicalization (spec §3)
    #   - xml:* inheritable attribute resolution
    #
    # Ported from canon (lutaml/canon) — adapted to build directly from
    # Moxml::Node rather than via a separate Nokogiri pass. Matches
    # canon's document-level node iteration (PIs and comments outside
    # the document root element).
    class DataModel
      def self.from_xml(xml_string)
        from_node(::Moxml.parse(xml_string))
      end

      def self.from_node(moxml_node)
        return build_from_document(moxml_node) if moxml_node.is_a?(::Moxml::Document)

        root = Nodes::RootNode.new
        root.add_child(build_node(moxml_node))
        root
      end

      # Build from a Moxml::Document. Matches canon's Nokogiri path:
      # the root element is added first, then all other document-level
      # children (PIs, comments) in document order.
      def self.build_from_document(document)
        root = Nodes::RootNode.new

        if document.root
          root.add_child(build_element_node(document.root))
          # Iterate ALL document children — not just the root element.
          # This captures PIs and comments that appear outside the
          # document element, which are part of the canonical form.
          document.children.each do |child|
            next if child.equal?(document.root)
            next if child.is_a?(::Moxml::Element)

            built = build_node(child)
            root.add_child(built) if built
          end
        end

        root
      end

      def self.build_node(moxml_node)
        case moxml_node
        when ::Moxml::Element then build_element_node(moxml_node)
        when ::Moxml::Text then build_text_node(moxml_node)
        when ::Moxml::Comment then build_comment_node(moxml_node)
        when ::Moxml::ProcessingInstruction then build_pi_node(moxml_node)
        end
      end

      def self.build_element_node(moxml_element)
        ns = moxml_element.namespace
        element = Nodes::ElementNode.new(
          name: moxml_element.name,
          namespace_uri: ns&.uri,
          prefix: ns&.prefix,
        )

        build_namespace_nodes(moxml_element, element)
        build_attribute_nodes(moxml_element, element)

        moxml_element.children.each do |child|
          built = build_node(child)
          element.add_child(built) if built
        end

        element
      end

      def self.build_namespace_nodes(moxml_element, element)
        moxml_element.in_scope_namespaces.each do |ns|
          element.add_namespace(
            Nodes::NamespaceNode.new(prefix: ns.prefix || "", uri: ns.uri),
          )
        end

        return if element.namespace_nodes.any? { |n| n.prefix == "xml" }

        element.add_namespace(
          Nodes::NamespaceNode.new(prefix: "xml", uri: XML_URI),
        )
      end

      def self.build_attribute_nodes(moxml_element, element)
        moxml_element.attributes.each do |attr|
          ns = attr.namespace
          element.add_attribute(
            Nodes::AttributeNode.new(
              name: attr.name,
              value: attr.value,
              namespace_uri: ns&.uri,
              prefix: ns&.prefix,
            ),
          )
        end
      end

      def self.build_text_node(moxml_text)
        Nodes::TextNode.new(value: moxml_text.content)
      end

      def self.build_comment_node(moxml_comment)
        Nodes::CommentNode.new(value: moxml_comment.content)
      end

      def self.build_pi_node(moxml_pi)
        Nodes::ProcessingInstructionNode.new(
          target: moxml_pi.target || moxml_pi.name,
          data: moxml_pi.content || "",
        )
      end

      def self.mark_all(node, value)
        node.in_node_set = value
        node.children.each { |child| mark_all(child, value) }
      end

      def self.mark_subset(root_node, matched)
        matched.each { |node| mark_node_and_descendants(node) }
        root_node.in_node_set = true
      end

      def self.mark_node_and_descendants(node)
        node.in_node_set = true
        node.children.each { |child| mark_node_and_descendants(child) }
      end

      private_class_method :build_from_document, :build_node,
                           :build_element_node, :build_namespace_nodes,
                           :build_attribute_nodes, :build_text_node,
                           :build_comment_node, :build_pi_node,
                           :mark_node_and_descendants
    end
  end
end
