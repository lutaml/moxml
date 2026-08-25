# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # A text run split out of a native text node that carried entity
      # markers. Value object: the moxml contract exposes text nodes as
      # separate children around entity references, while libleptris
      # stores them as one marker-bearing text node.
      class TextSegment
        attr_accessor :parent

        attr_reader :content

        def initialize(content, parent = nil)
          @content = content
          @parent = parent
        end

        def ==(other)
          other.is_a?(self.class) && content == other.content
        end
      end
    end
  end
end
