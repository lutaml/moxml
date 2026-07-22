# frozen_string_literal: true

module Moxml
  module Signature
    # Reference generation + SignatureValue computation per spec §3.1.
    #
    # Flow:
    #   1. For each Reference in signed_info.references:
    #      a. Resolve URI (same-document or octet).
    #      b. Apply each Transform in order.
    #      c. Compute digest via DigestMethod.
    #      d. Store base64 digest on Reference#digest_value.
    #   2. Serialize SignedInfo.
    #   3. Canonicalize per CanonicalizationMethod.
    #   4. Sign via SignatureMethod#sign(canonical_octets, key).
    #   5. Set signature.signature_value.
    class Signer
      attr_reader :context, :signature, :document, :key

      def initialize(context:, signature:, document:, key:)
        @context = context
        @signature = signature
        @document = document
        @key = key
      end

      def sign
        Algorithms.load_builtins!

        signature.signed_info.references.each do |ref|
          digest = compute_reference_digest(ref)
          ref.digest_value = digest
        end

        signature.signature_value = Model::SignatureValue.new(
          value: compute_signature_value,
        )
        signature
      end

      private

      def compute_reference_digest(reference)
        resolver = ReferenceResolver.new(context: context, document: document)
        input = resolver.resolve(reference.uri)
        pipeline = TransformPipeline.new(context: context, signature_element: nil)
        transformed = pipeline.apply(input, reference.transforms)
        canonical = pipeline.to_octets(transformed, reference)
        digest_algo = Algorithms.lookup(:digest, reference.digest_method.algorithm).new
        digest_algo.digest_base64(canonical)
      end

      def compute_signature_value
        signed_info = signature.signed_info
        serializer = Serializer.new(context: context)
        signed_info_doc = serializer.serialize_signed_info(signed_info)

        c14n_uri = signed_info.canonicalization_method.algorithm
        c14n_klass = Algorithms.lookup(:canonicalization, c14n_uri)
        c14n = c14n_klass.new(identifier_uri: c14n_uri)
        canonical_octets = c14n.canonicalize(signed_info_doc.root)

        sm_uri = signed_info.signature_method.algorithm
        sm_klass = Algorithms.lookup(:signature_method, sm_uri)
        sm = sm_klass.new(
          identifier_uri: sm_uri,
          parameters: signed_info.signature_method.parameters,
        )
        sm.sign(canonical_octets, key)
      end
    end
  end
end
