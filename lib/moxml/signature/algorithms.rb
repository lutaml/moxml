# frozen_string_literal: true

module Moxml
  module Signature
    # Open-closed registry of W3C XML Signature algorithms keyed by URI.
    #
    # Adding a new algorithm:
    #   1. Subclass the relevant base (DigestBase, SignatureMethodBase, etc.)
    #   2. Declare `identifier "http://..."` on the subclass.
    #   3. Add an autoload entry below and a reference in `load_builtins!`.
    #
    # No edits to existing classes are required to add a new algorithm.
    module Algorithms
      CATEGORIES = %i[digest signature_method canonicalization transform].freeze

      class << self
        def registry
          @registry ||= CATEGORIES.to_h { |c| [c, {}] }
        end

        def register(category, uri, klass)
          validate_category!(category)
          registry[category][uri] = klass
          klass
        end

        def lookup(category, uri)
          load_builtins! unless @builtins_loaded
          registry[category][uri] ||
            raise(UnknownAlgorithm.new(category, uri))
        end

        def registered?(category, uri)
          load_builtins! unless @builtins_loaded
          registry[category].key?(uri)
        end

        def [](category)
          validate_category!(category)
          registry[category]
        end

        # Forces autoload of every built-in algorithm class so that
        # self-registration runs. Pure autoload — no `require` calls.
        def load_builtins!
          return if @builtins_loaded

          # Digests
          SHA1
          SHA224
          SHA256
          SHA384
          SHA512
          # Signature methods
          RsaPkcs1Sha
          HmacSha
          EcdsaSha
          DsaSha
          # Canonicalization
          ExcC14n10
          InclusiveC14n10
          InclusiveC14n11
          # Transforms
          Base64Transform
          EnvelopedSignatureTransform

          @builtins_loaded = true
        end

        private

        def validate_category!(category)
          return if CATEGORIES.include?(category)

          raise ArgumentError,
                "unknown algorithm category #{category.inspect}; " \
                "expected one of #{CATEGORIES.inspect}"
        end
      end

      # Base classes — interfaces only.
      autoload :DigestBase, "moxml/signature/algorithms/digest_base"
      autoload :SignatureMethodBase,
               "moxml/signature/algorithms/signature_method_base"
      autoload :CanonicalizationBase,
               "moxml/signature/algorithms/canonicalization_base"
      autoload :TransformBase, "moxml/signature/algorithms/transform_base"

      # Digests
      autoload :SHA1, "moxml/signature/algorithms/sha1"
      autoload :SHA224, "moxml/signature/algorithms/sha224"
      autoload :SHA256, "moxml/signature/algorithms/sha256"
      autoload :SHA384, "moxml/signature/algorithms/sha384"
      autoload :SHA512, "moxml/signature/algorithms/sha512"

      # Signature methods
      autoload :RsaPkcs1Sha, "moxml/signature/algorithms/rsa_pkcs1_sha"
      autoload :HmacSha, "moxml/signature/algorithms/hmac_sha"
      autoload :EcdsaSha, "moxml/signature/algorithms/ecdsa_sha"
      autoload :DsaSha, "moxml/signature/algorithms/dsa_sha"

      # Canonicalization (delegates to Moxml::C14n engine)
      autoload :ExcC14n10, "moxml/signature/algorithms/exc_c14n_10"
      autoload :InclusiveC14n10, "moxml/signature/algorithms/inclusive_c14n_10"
      autoload :InclusiveC14n11, "moxml/signature/algorithms/inclusive_c14n_11"

      # Transforms
      autoload :Base64Transform, "moxml/signature/algorithms/base64_transform"
      autoload :EnvelopedSignatureTransform,
               "moxml/signature/algorithms/enveloped_signature_transform"
    end
  end
end
