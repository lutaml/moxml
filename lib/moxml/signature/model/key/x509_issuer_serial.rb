# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      module Key
        # ds:X509IssuerSerial — deprecated in favor of X509Digest.
        class X509IssuerSerial
          attr_accessor :issuer_name, :serial_number

          def initialize(issuer_name:, serial_number:)
            @issuer_name = issuer_name
            @serial_number = serial_number
          end
        end
      end
    end
  end
end
