# frozen_string_literal: true

# Lifecycle record: the :libxml adapter is deprecated (#491); this wrapper dies with it.

module Moxml
  module Adapter
    module CustomizedLibxml
      class EntityReference
        attr_reader :name

        def initialize(name)
          @name = name
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
