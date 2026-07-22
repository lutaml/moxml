# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class Transforms
        attr_accessor :transforms

        def initialize(transforms: [])
          @transforms = Array(transforms)
        end

        def <<(transform)
          @transforms << transform
          self
        end

        def each(&block)
          @transforms.each(&block)
        end

        def empty?
          @transforms.empty?
        end

        def size
          @transforms.size
        end

        def length
          @transforms.size
        end
      end
    end
  end
end
