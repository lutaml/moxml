# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      # Generic algorithm method element. Used for CanonicalizationMethod and
      # SignatureMethod, both of which are `<Foo Algorithm="uri" />` shape.
      class AlgorithmMethod
        attr_accessor :algorithm, :parameters

        def initialize(algorithm:, parameters: {})
          @algorithm = algorithm
          @parameters = parameters
        end
      end
    end
  end
end
