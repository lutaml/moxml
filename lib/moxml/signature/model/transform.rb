# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class Transform
        attr_accessor :algorithm, :parameters

        def initialize(algorithm:, parameters: {})
          @algorithm = algorithm
          @parameters = parameters
        end
      end
    end
  end
end
