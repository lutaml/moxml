# frozen_string_literal: true

module Moxml
  class EntityReference < Node
    def content
      ""
    end

    def text
      ""
    end

    def name
      adapter.entity_reference_name(@native)
    end

    def to_xml(*)
      "&#{name};"
    end

    def ==(other)
      self.class == other.class && @native == other.native
    end

    def identifier
      name
    end
  end
end
