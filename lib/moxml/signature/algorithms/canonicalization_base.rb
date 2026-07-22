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

        def initialize(identifier_uri: nil, with_comments: nil,
                       inclusive_namespaces: [])
          @identifier_uri = identifier_uri
          @with_comments = with_comments.nil? ? uri_has_comments?(identifier_uri) : with_comments
          @inclusive_namespaces = inclusive_namespaces || []
        end

        def canonicalize(node)
          engine.canonicalize(
            node,
            with_comments: @with_comments,
            inclusive_namespaces: @inclusive_namespaces,
          )
        end

        private

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
