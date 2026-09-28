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
        @source_map = {}
        return build_from_document(moxml_node) if moxml_node.is_a?(::Moxml::Document)

        root = Nodes::RootNode.new
        built = build_node(moxml_node, [0])
        root.add_child(built) if built
        root
      end

      # Position keys for subset selection: adapters mint fresh
      # wrappers per traversal, so XPath-matched wrappers cannot be
      # keyed by object identity. Both sides instead compute the same
      # child-index path — the build walks dm children in order, the
      # match side climbs parents counting buildable siblings (the
      # same types build_node answers non-nil for).
      class << self
        attr_reader :source_map
      end

      BUILDABLE_TYPES = [::Moxml::Element, ::Moxml::Text, ::Moxml::Cdata,
                         ::Moxml::Comment,
                         ::Moxml::ProcessingInstruction].freeze

      def self.buildable?(node)
        BUILDABLE_TYPES.any? { |type| node.is_a?(type) }
      end

      # Path key of a matched wrapper relative to the source the data
      # model was built from; nil when the wrapper is outside it.
      # Attributes extend their owner's path with [:attribute, index].
      # The adapter comes from the caller: the Attribute contract
      # keeps its own adapter hop protected.
      def self.path_key_for(wrapper, source, adapter)
        case wrapper
        when ::Moxml::Attribute
          owner = wrapper.parent
          unless owner.is_a?(::Moxml::Element)
            # XPath results are re-wrapped from natives: attribute
            # wrappers carry no minted parent. The adapter answers
            # the owner element instead.
            owner_native = adapter.attribute_element(wrapper.native)
            owner = owner_native && ::Moxml::Node.wrap(owner_native, wrapper.context)
          end
          return nil unless owner.is_a?(::Moxml::Element)

          owner_path = node_path(owner, source)
          return nil unless owner_path

          idx = owner.attributes.index { |a| a == wrapper }
          return nil unless idx

          owner_path + [:attribute, idx]
        when *BUILDABLE_TYPES
          node_path(wrapper, source)
        end
      end

      def self.node_path(node, source)
        parts = []
        cur = node
        loop do
          if !source.is_a?(::Moxml::Document) && cur.equal?(source)
            parts.unshift(0)
            return parts
          end

          parent = cur.parent
          return nil unless parent

          idx = parent.children.select { |c| buildable?(c) }.index { |c| c == cur }
          return nil unless idx

          parts.unshift(idx)
          return parts if source.is_a?(::Moxml::Document) && parent.is_a?(::Moxml::Document)

          cur = parent
        end
      end

      # Build from a Moxml::Document. Matches canon's Nokogiri path:
      # the root element is added first, then all other document-level
      # children (PIs, comments) in document order.
      def self.build_from_document(document)
        root = Nodes::RootNode.new

        if document.root
          # Document-level children (PIs and comments outside the
          # document element) are part of the canonical form and must
          # keep document order — a leading PI canonicalizes before the
          # root element (spec §2.1; the native engines emit it there
          # too). The document element is the first element child: some
          # adapters mint fresh wrappers per children call, so wrapper
          # identity cannot locate it.
          seen_root = false
          idx = 0
          document.children.each do |child|
            if child.is_a?(::Moxml::Element)
              next if seen_root

              seen_root = true
            end

            built = build_node(child, [idx])
            next unless built

            root.add_child(built)
            idx += 1
          end
          root.add_child(build_element_node(document.root, [idx])) unless seen_root
        end

        root
      end

      def self.build_node(moxml_node, path)
        case moxml_node
        when ::Moxml::Element then build_element_node(moxml_node, path)
        # CDATA sections are character data to canonicalization: their
        # content is emitted as escaped text (spec §3.1 "text nodes").
        when ::Moxml::Text, ::Moxml::Cdata then build_text_node(moxml_node, path)
        when ::Moxml::Comment then build_comment_node(moxml_node, path)
        when ::Moxml::ProcessingInstruction then build_pi_node(moxml_node, path)
        end
      end

      def self.build_element_node(moxml_element, path)
        ns = moxml_element.namespace
        element = Nodes::ElementNode.new(
          name: moxml_element.name,
          namespace_uri: ns&.uri,
          prefix: ns&.prefix,
        )
        source_map[path] = element

        build_namespace_nodes(moxml_element, element)
        build_attribute_nodes(moxml_element, element, path)

        idx = 0
        moxml_element.children.each do |child|
          built = build_node(child, path + [idx])
          next unless built

          element.add_child(built)
          idx += 1
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

      def self.build_attribute_nodes(moxml_element, element, path)
        moxml_element.attributes.each_with_index do |attr, idx|
          ns = attr.namespace
          # The xml prefix is reserved: any attribute bound to the XML
          # namespace URI renders (and sorts) as prefix "xml" regardless
          # of how the adapter reports it (spec §2.3 attribute-axis key).
          prefix = ns&.prefix
          uri = ns&.uri
          if prefix == "xml" || uri == XML_URI
            prefix = "xml"
            uri = XML_URI
          end
          node = Nodes::AttributeNode.new(
            name: attr.name,
            value: attr.value,
            namespace_uri: uri,
            prefix: prefix,
          )
          source_map[path + [:attribute, idx]] = node
          element.add_attribute(node)
        end
      end

      def self.build_text_node(moxml_text, path)
        node = Nodes::TextNode.new(value: moxml_text.content)
        source_map[path] = node
        node
      end

      def self.build_comment_node(moxml_comment, path)
        node = Nodes::CommentNode.new(value: moxml_comment.content)
        source_map[path] = node
        node
      end

      def self.build_pi_node(moxml_pi, path)
        node = Nodes::ProcessingInstructionNode.new(
          target: moxml_pi.target || moxml_pi.name,
          data: moxml_pi.content || "",
        )
        source_map[path] = node
        node
      end

      def self.mark_all(node, value)
        node.in_node_set = value
        node.children.each { |child| mark_all(child, value) }
      end

      # Mark an XPath-selected subset: reset the whole model, then
      # flag each matched node by position path. Node-set semantics
      # follow the enveloped-signature interop (libxml2/xmlsec): an
      # included element renders with its namespaces, attributes and
      # DIRECT character data, but child ELEMENTS render only if
      # matched too — an unmatched Signature subtree stays out even
      # though its ancestors are matched.
      def self.mark_subset_paths(root_node, paths)
        mark_all(root_node, false)
        paths.each do |path|
          node = lookup_path(root_node, path)
          next unless node

          if node.is_a?(Nodes::ElementNode)
            node.in_node_set = true
            node.namespace_nodes.each { |ns| ns.in_node_set = true }
            node.attribute_nodes.each { |attr| attr.in_node_set = true }
            node.children.each do |child|
              child.in_node_set = true unless child.is_a?(Nodes::ElementNode)
            end
          else
            node.in_node_set = true
          end
        end
      end

      def self.lookup_path(root_node, path)
        cur = root_node
        i = 0
        while i < path.length && path[i].is_a?(Integer)
          cur = cur.children[path[i]]
          return nil unless cur

          i += 1
        end
        return cur if i >= path.length
        return nil unless path[i] == :attribute

        cur.attribute_nodes[path[i + 1]]
      end

      private_class_method :build_from_document, :build_node,
                           :build_element_node, :build_namespace_nodes,
                           :build_attribute_nodes, :build_text_node,
                           :build_comment_node, :build_pi_node,
                           :mark_all, :lookup_path
    end
  end
end
