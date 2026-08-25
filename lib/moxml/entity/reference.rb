# frozen_string_literal: true

module Moxml
  module Entity
    # A named entity reference (&name;) as a value object, for
    # adapters whose native trees cannot represent entity references
    # (ox stores them in the tree; rexml and leptris carry them
    # alongside). Adapter-specific namespaces alias this class so
    # node_type dispatch keeps working.
    class Reference
      attr_reader :name
      attr_accessor :parent

      def initialize(name)
        @name = name
        @parent = nil
      end

      def to_xml
        "&#{name};"
      end

      def ==(other)
        other.is_a?(Reference) && name == other.name
      end
    end
  end
end
