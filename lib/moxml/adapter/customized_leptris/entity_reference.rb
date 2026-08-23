# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # Wrapper for an entity reference. libleptris expands the five
      # built-in entities at parse time and does not support custom
      # ones, so Moxml's entity-marker pipeline hands these wrappers
      # back to the document for round-trip preservation.
      class EntityReference
        attr_accessor :parent

        attr_reader :name

        def initialize(name)
          @name = name
          @parent = nil
        end

        def to_xml
          "&#{name};"
        end

        def ==(other)
          other.is_a?(self.class) && name == other.name
        end
      end
    end
  end
end
