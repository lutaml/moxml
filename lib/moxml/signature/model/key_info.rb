# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class KeyInfo
        attr_accessor :id, :key_name, :key_value, :x509_data,
                      :raw_elements

        def initialize(id: nil, key_name: nil, key_value: nil,
                       x509_data: nil, raw_elements: [])
          @id = id
          @key_name = key_name
          @key_value = key_value
          @x509_data = x509_data
          @raw_elements = raw_elements
        end
      end
    end
  end
end
