# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Base wrapper class for LibXML nodes
      #
      # This wrapper hides LibXML's strict document ownership model,
      # allowing nodes to be moved between documents transparently.
      # Similar pattern to Ox adapter's customized classes.
      #
      # The Libxml adapter owns wrapper type mapping in one place so the
      # wrapper classes do not duplicate node-type knowledge.
      class Node
        attr_reader :native

        def initialize(native_node)
          @native = native_node
        end

        # Swap the wrapped native node. Used by the Libxml adapter when
        # libxml-ruby's content= setter would silently re-escape stored
        # text; replacing the node with a fresh raw-storage instance is
        # the only way to preserve verbatim content.
        def replace_native!(fresh)
          @native = fresh
        end

        # Compare wrappers based on their native nodes. Either side
        # may arrive double-wrapped (a Customized node stored as
        # another wrapper's native); LibXML's eql? raises on the
        # class mismatch, so unwrap both before comparing.
        def ==(other)
          return false unless other

          mine = @native.is_a?(CustomizedLibxml::Node) ? @native.native : @native
          theirs = other.is_a?(self.class) ? other.native : other
          theirs = theirs.native while theirs.is_a?(CustomizedLibxml::Node)
          mine == theirs
        end

        alias eql? ==

        def hash
          @native.hash
        end

        # Check if node has a document
        def document_present?
          @native.is_a?(::LibXML::XML::Node) && !@native.doc.nil?
        end

        # Get the document this node belongs to
        def document
          @native.doc if document_present?
        end
      end
    end
  end
end
