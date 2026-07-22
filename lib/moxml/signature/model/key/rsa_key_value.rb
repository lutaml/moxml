# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      module Key
        # ds:RSAKeyValue — base64-encoded CryptoBinary Modulus + Exponent.
        class RSAKeyValue
          attr_accessor :modulus, :exponent

          def initialize(modulus:, exponent:)
            @modulus = modulus
            @exponent = exponent
          end
        end
      end
    end
  end
end
