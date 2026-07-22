# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      module Key
        # dsig11:X509Digest — algorithm URI + base64 digest of a cert.
        class X509Digest
          attr_accessor :algorithm, :digest

          def initialize(algorithm:, digest:)
            @algorithm = algorithm
            @digest = digest
          end
        end
      end
    end
  end
end
