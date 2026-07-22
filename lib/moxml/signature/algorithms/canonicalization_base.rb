# frozen_string_literal: true

require "openssl"

module Moxml
  module Signature
    module Algorithms
      # Base class for canonicalization algorithms.
      #
      # Subclasses declare `identifier "http://..."` (once per URI, including
      # the #WithComments variant if applicable) and implement #canonicalize.
      #
      # Canonicalizers operate on a Moxml::Node subtree and return a UTF-8
      # String of octets. They never touch adapter internals directly.
      class CanonicalizationBase
        class << self
          attr_reader :identifier_uris, :with_comments_default

          # Canonicalization can be used as a transform (spec §6.6.1).
          # Input: octet stream or node-set. Output: octet stream.
          def input_type; :nodeset; end
          def output_type; :octets; end

          def identifier(uri, with_comments: false)
            @identifier_uris ||= []
            @identifier_uris << { uri: uri, with_comments: with_comments }
            Algorithms.register(:canonicalization, uri, self)
          end

          def for_uri(uri)
            new(identifier_uri: uri)
          end
        end

        attr_reader :identifier_uri, :with_comments

        # Accepts all possible transform-construction kwargs so canonicalization
        # algorithms can be transparently used as transforms (spec §6.6.1).
        def initialize(identifier_uri: nil, with_comments: nil,
                       inclusive_namespaces: [], **_unused)
          @identifier_uri = identifier_uri
          @with_comments = if with_comments.nil?
                             uri_has_comments?(identifier_uri)
                           else
                             with_comments
                           end
          @inclusive_namespaces = inclusive_namespaces || []
        end

        def canonicalize(node)
          engine.canonicalize(
            node,
            with_comments: @with_comments,
            inclusive_namespaces: @inclusive_namespaces,
          )
        end

        # When a canonicalization algorithm is used as a transform
        # (spec §6.6.1), it presents the same #transform interface as
        # other transforms. Input is a node (or octets that get parsed).
        def transform(input)
          node = parse_if_octets(input)
          canonicalize(node)
        end

        private

        def parse_if_octets(input)
          return input if input.is_a?(::Moxml::Node)

          # Octet-stream input: parse as XML, canonicalize the root.
          # (Caller is expected to have a context-aware parser; for the
          # c14n-as-transform case we use a generic empty-context parse.)
          ::Moxml.parse(input.to_s).root
        end

        def uri_has_comments?(uri)
          return false if uri.nil?

          uri.end_with?("#WithComments")
        end

        def engine
          raise NotImplementedError,
                "#{self.class} must implement #engine or override #canonicalize"
        end
      end
    end
  end
end
