# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class Signature
        attr_accessor :id, :signed_info, :signature_value,
                      :key_info, :objects

        def initialize(id: nil, signed_info: nil, signature_value: nil,
                       key_info: nil, objects: [])
          @id = id
          @signed_info = signed_info
          @signature_value = signature_value
          @key_info = key_info
          @objects = objects
        end
      end
    end
  end
end
