# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Base wrapper class for LibXML nodes
      #
      # This wrapper hides LibXML's strict document ownership model,
      # allowing nodes to be moved between documents transparently.
      # Similar pattern to Ox adapter's customized classes.
      class Node
        attr_reader :native

        def initialize(native_node)
          @native = native_node
        end

        # Compare wrappers based on their native nodes
        def ==(other)
          return false unless other

          other_native = other.respond_to?(:native) ? other.native : other
          @native == other_native
        end

        alias eql? ==

        def hash
          @native.hash
        end

        # Check if node has a document
        def document_present?
          @native.respond_to?(:doc) && !@native.doc.nil?
        end

        # Get the document this node belongs to
        def document
          @native.doc if document_present?
        end
      end
    end
  end
end
