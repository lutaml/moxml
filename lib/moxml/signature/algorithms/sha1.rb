# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      class SHA1 < DigestBase
        identifier "http://www.w3.org/2000/09/xmldsig#sha1"
        digest_bits 160
        openssl_digest_name "SHA1"
      end
    end
  end
end
