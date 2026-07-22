# frozen_string_literal: true

module Moxml
  module C14n
    # Inclusive Canonical XML 1.0 (https://www.w3.org/TR/xml-c14n/)
    #
    # Unlike exclusive C14N, inclusive C14N "attracts" ancestor context:
    # at the apex element, ALL in-scope namespaces are rendered, including
    # those inherited from ancestors outside the canonicalization subset.
    #
    # xml:* inheritable attributes (xml:lang, xml:space) are also inherited
    # from the nearest ancestor in which they are declared.
    #
    # Implementation: delegates to the canon-derived Processor pipeline
    # (DataModel + NamespaceHandler + AttributeHandler + XmlBaseHandler).
    class Inclusive10
      # rubocop:disable Lint/UnusedMethodArgument -- signature must match Exclusive
      def canonicalize(node_or_xml, with_comments: false, inclusive_namespaces: [])
        # rubocop:enable Lint/UnusedMethodArgument
        root = coerce_to_data_model(node_or_xml)
        Processor.new(with_comments: with_comments).process(root)
      end

      private

      def coerce_to_data_model(node_or_xml)
        return node_or_xml if node_or_xml.is_a?(Nodes::RootNode)

        case node_or_xml
        when ::Moxml::Document, ::Moxml::Node
          DataModel.from_node(node_or_xml)
        when String
          DataModel.from_xml(node_or_xml)
        else
          raise ArgumentError,
                "Inclusive10#canonicalize expects a Moxml::Node, " \
                "Moxml::Document, or XML String; got #{node_or_xml.class}"
        end
      end
    end
  end
end
