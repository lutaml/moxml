# frozen_string_literal: true

require_relative "node"

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML element nodes
      #
      # This wrapper provides automatic document import when adding children,
      # solving LibXML's strict document ownership requirement.
      class Element < Node
        # Add a child to this element, handling document import automatically
        def add_child(child)
          child_native = child.respond_to?(:native) ? child.native : child

          # Check if child needs to be imported
          if needs_import?(child_native)
            imported = @native.doc.import(child_native)
            @native << imported
          else
            @native << child_native
          end
        end

        private

        def needs_import?(child_node)
          return false unless @native.respond_to?(:doc)
          return false unless @native.doc
          return false unless child_node.respond_to?(:doc)
          return false unless child_node.doc

          child_node.doc != @native.doc
        end
      end
    end
  end
end
