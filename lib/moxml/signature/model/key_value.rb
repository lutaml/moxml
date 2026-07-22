# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class KeyValue
        attr_accessor :rsa_key_value, :dsa_key_value, :ec_key_value,
                      :raw_element

        def initialize(rsa_key_value: nil, dsa_key_value: nil,
                       ec_key_value: nil, raw_element: nil)
          @rsa_key_value = rsa_key_value
          @dsa_key_value = dsa_key_value
          @ec_key_value = ec_key_value
          @raw_element = raw_element
        end
      end
    end
  end
end
