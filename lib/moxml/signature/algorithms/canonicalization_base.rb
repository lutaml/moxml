# frozen_string_literal: true

require "openssl"

module Moxml
  module Signature
    module Algorithms
      # Base class for canonicalization algorithms.
      #
      # Subclasses declare `identifier "http://..."` and implement #engine
      # (returning a Moxml::C14n::* walker). Canonicalizers operate on a
      # Moxml::Node subtree and return UTF-8 octets.
      #
      # Canonicalization algorithms can also be used as transforms per
      # spec §6.6.1. The base class provides the #transform method that
      # adapts the canonicalize interface to the transform pipeline.
      class CanonicalizationBase
        class << self
          # Canonicalization presents the transform interface (spec §6.6.1).
          # Input: octet stream or node-set. Output: octet stream.
          def input_type; :nodeset; end

          def output_type; :octets; end

          def identifier(uri)
            Algorithms.register(:canonicalization, uri, self)
          end

          def for_uri(uri, **opts)
            new(identifier_uri: uri, **opts)
          end
        end

        attr_reader :identifier_uri, :with_comments, :inclusive_namespaces,
                    :context

        # `context:` is required when this algorithm is used as a transform
        # so that octet-stream input can be parsed with the same adapter
        # the caller used for the rest of the document.
        def initialize(identifier_uri: nil, with_comments: nil,
                       inclusive_namespaces: [], context: nil, **_unused)
          @identifier_uri = identifier_uri
          @with_comments = with_comments.nil? ? uri_has_comments?(identifier_uri) : with_comments
          @inclusive_namespaces = inclusive_namespaces || []
          @context = context
        end

        def canonicalize(node)
          engine.canonicalize(
            node,
            with_comments: @with_comments,
            inclusive_namespaces: @inclusive_namespaces,
          )
        end

        # Adapt to the transform interface (spec §6.6.1). Octet-stream
        # input is parsed using the same Moxml::Context the caller used;
        # this preserves the byte-exact invariant across adapters.
        def transform(input)
          return canonicalize(input) if input.is_a?(::Moxml::Node)

          if context.nil?
            raise TransformError,
                  "canonicalization transform requires a context to parse " \
                  "octet-stream input; none was provided"
          end

          parsed = context.parse(input.to_s)
          canonicalize(parsed.root)
        end

        private

        def uri_has_comments?(uri)
          return false if uri.nil?

          uri.end_with?("#WithComments")
        end

        def engine
          raise NotImplementedError,
                "#{self.class} must implement #engine"
        end
      end
    end
  end
end
