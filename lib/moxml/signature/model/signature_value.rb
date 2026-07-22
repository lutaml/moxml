# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class SignatureValue
        attr_accessor :id, :value

        def initialize(id: nil, value: nil)
          @id = id
          @value = value
        end
      end
    end
  end
end
