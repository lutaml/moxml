# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class DigestMethod
        attr_accessor :algorithm

        def initialize(algorithm:)
          @algorithm = algorithm
        end
      end
    end
  end
end
