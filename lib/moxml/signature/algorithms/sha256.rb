# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      class SHA256 < DigestBase
        identifier "http://www.w3.org/2001/04/xmlenc#sha256"
        digest_bits 256
        openssl_digest_name "SHA256"
      end
    end
  end
end
