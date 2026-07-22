# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Namespace node. Prefix is empty string for the default namespace.
      class NamespaceNode < Node
        attr_reader :prefix, :uri

        def initialize(prefix:, uri:)
          super()
          @prefix = prefix
          @uri = uri
        end

        def name
          prefix.to_s
        end

        def node_type
          :namespace
        end

        # Local name is the prefix (empty string for default namespace).
        # Used by ElementNode#sorted_namespace_nodes for sort order.
        def local_name
          prefix.to_s
        end

        def default_namespace?
          prefix.nil? || prefix.empty?
        end

        # The `xml` namespace is implicit and never rendered.
        def xml_namespace?
          prefix == "xml" && uri == Moxml::C14n::XML_URI
        end
      end
    end
  end
end
