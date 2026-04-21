# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedOx
      class EntityReference
        attr_reader :name
        attr_accessor :parent

        def initialize(name)
          @name = name
          @parent = nil
        end

        def to_xml
          "&#{@name};"
        end

        def ==(other)
          other.is_a?(self.class) && @name == other.name
        end
      end
    end
  end
end
