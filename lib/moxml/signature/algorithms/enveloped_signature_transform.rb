# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Enveloped Signature Transform (W3C §6.6.4).
      #
      # Removes the containing ds:Signature element from the node-set so the
      # signature does not include itself in its own digest calculation.
      #
      # Semantics during signing: `signature_element` is nil (the Signature
      # has not been attached to the document yet), so the transform is a
      # no-op — the document contains no Signature to exclude.
      #
      # Semantics during verification: `signature_element` is the Signature
      # element being verified. The transform detaches it (and its
      # descendants) from a deep copy of the input so the canonicalizer
      # walks a tree without the Signature.
      class EnvelopedSignatureTransform < TransformBase
        identifier "http://www.w3.org/2000/09/xmldsig#enveloped-signature"

        def self.input_type; :nodeset; end
        def self.output_type; :nodeset; end

        def transform(input)
          return input if @signature_element.nil?

          # If the signature is not within the input subtree, no-op.
          return input unless signature_within?(input)

          working_copy = deep_copy(input)
          remove_signature_within(working_copy)
          working_copy
        end

        private

        def signature_within?(input)
          !find_signature_element(input).nil?
        end

        def remove_signature_within(node)
          sig = find_signature_element(node)
          sig&.remove
        end

        def find_signature_element(node)
          return nil unless node
          return node if signature_element?(node)

          children = node.children if node.is_a?(::Moxml::Node)
          children&.each do |child|
            found = find_signature_element(child)
            return found if found
          end
          nil
        end

        def signature_element?(node)
          node.is_a?(::Moxml::Element) &&
            node.name == "Signature" &&
            node.namespace_uri == DSIG_NS
        end

        def deep_copy(input)
          case input
          when ::Moxml::Document
            @context.parse(input.root.to_xml(indent: 0))
          when ::Moxml::Element
            wrapper = @context.parse("<__wrap__>#{input.to_xml(indent: 0)}</__wrap__>")
            wrapper.root.children.first
          else
            input
          end
        end
      end
    end
  end
end
