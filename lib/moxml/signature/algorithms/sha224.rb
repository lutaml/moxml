# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      class SHA224 < DigestBase
        identifier "http://www.w3.org/2001/04/xmldsig-more#sha224"
        digest_bits 224
        openssl_digest_name "SHA224"
      end
    end
  end
end
