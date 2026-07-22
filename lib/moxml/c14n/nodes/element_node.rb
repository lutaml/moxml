# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Element node in the C14N data model.
      class ElementNode < Node
        attr_reader :name, :namespace_uri, :prefix, :namespace_nodes,
                    :attribute_nodes

        def initialize(name:, namespace_uri: nil, prefix: nil)
          super()
          @name = name
          @namespace_uri = namespace_uri
          @prefix = prefix
          @namespace_nodes = []
          @attribute_nodes = []
        end

        def node_type
          :element
        end

        def qname
          prefix.nil? || prefix.empty? ? name : "#{prefix}:#{name}"
        end

        def add_namespace(namespace_node)
          namespace_node.parent = self
          @namespace_nodes << namespace_node
        end

        def add_attribute(attribute_node)
          attribute_node.parent = self
          @attribute_nodes << attribute_node
        end

        # Namespace nodes sorted lexicographically by local name (prefix).
        # Per W3C C14N 1.0 §2.3 / 1.1 §2.3, default namespace sorts first.
        def sorted_namespace_nodes
          @namespace_nodes.sort_by { |ns| ns.local_name.to_s }
        end

        # Attribute nodes sorted by namespace URI then local name
        # (W3C C14N 1.0 §2.4 / 1.1 §2.4).
        def sorted_attribute_nodes
          @attribute_nodes.sort_by do |attr|
            [attr.namespace_uri.to_s, attr.local_name]
          end
        end

        def text_content
          children.map(&:text_content).join
        end

        def to_s
          "<#{qname}>"
        end
      end
    end
  end
end
