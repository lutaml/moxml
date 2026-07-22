# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      class SHA384 < DigestBase
        identifier "http://www.w3.org/2001/04/xmldsig-more#sha384"
        digest_bits 384
        openssl_digest_name "SHA384"
      end
    end
  end
end
