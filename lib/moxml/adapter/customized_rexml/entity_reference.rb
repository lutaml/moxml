# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedRexml
      class EntityReference
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def ==(other)
          other.is_a?(self.class) && @name == other.name
        end
      end
    end
  end
end
