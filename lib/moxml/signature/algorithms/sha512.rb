# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      class SHA512 < DigestBase
        identifier "http://www.w3.org/2001/04/xmlenc#sha512"
        digest_bits 512
        openssl_digest_name "SHA512"
      end
    end
  end
end
