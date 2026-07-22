# frozen_string_literal: true

module Moxml
  module Signature
    # Core Validation per spec §3.2, with the safe ordering prescribed by
    # Best Practice 1: verify SignatureValue BEFORE running any reference
    # transforms (which could be hostile).
    class Verifier
      attr_reader :context, :document, :key, :key_map

      def initialize(context:, document:, key: nil, key_map: {}, **_options)
        @context = context
        @document = document
        @key = key
        @key_map = key_map || {}
      end

      def verify
        Algorithms.load_builtins!
        signatures = find_signatures

        results = signatures.map { |sig_elem| verify_one(sig_elem) }
        VerificationResult.new(results: results)
      end

      private

      def find_signatures
        document.xpath("//ds:Signature", "ds" => DSIG_NS)
          .grep(::Moxml::Element)
      end

      def verify_one(signature_element)
        signature = Parser.new(context: context).parse(signature_element)
        signature_value_ok, error = verify_signature_value(signature, signature_element)
        reference_results = if signature_value_ok
                              verify_references(signature, signature_element)
                            else
                              []
                            end

        SingleVerificationResult.new(
          signature_id: signature.id,
          signature_valid: signature_value_ok,
          references: reference_results,
          error: error,
        )
      end

      # Returns [Boolean, ErrorOrNil] so the caller can attach the error
      # to the result for debugging. The error is never raised — Best
      # Practice 1 says authenticate first; surfacing why auth failed is
      # an application concern, not a panic.
      def verify_signature_value(signature, signature_element)
        return [false, nil] if signature.signature_value.nil?
        return [false, nil] if signature.signature_value.value.nil?

        signed_info_elem = signature_element.at_xpath(
          "./ds:SignedInfo", "ds" => DSIG_NS
        )
        return [false, nil] if signed_info_elem.nil?

        c14n_uri = signature.signed_info.canonicalization_method&.algorithm
        return [false, nil] if c14n_uri.nil?

        canonical = canonicalize_signed_info(c14n_uri, signed_info_elem)
        sm_uri = signature.signed_info.signature_method.algorithm
        sm = Algorithms.lookup(:signature_method, sm_uri).new(
          identifier_uri: sm_uri,
          parameters: signature.signed_info.signature_method.parameters,
        )
        verification_key = resolve_key(signature)
        return [false, nil] if verification_key.nil?

        ok = sm.verify(canonical, verification_key, signature.signature_value.value)
        [ok, nil]
      rescue VerificationError, UnknownAlgorithm => e
        [false, e]
      end

      # Canonicalize the original SignedInfo element as it appears in the
      # document. Re-serializing the parsed model would change namespace
      # prefixes (e.g. SignedInfo → ds:SignedInfo) and break byte-exact
      # verification.
      def canonicalize_signed_info(c14n_uri, signed_info_elem)
        Algorithms.lookup(:canonicalization, c14n_uri)
          .new(identifier_uri: c14n_uri)
          .canonicalize(signed_info_elem)
      end

      def resolve_key(signature)
        return key if key
        return nil unless signature.key_info

        KeyExtractor.new(key_map: key_map).extract(signature.key_info)
      end

      def verify_references(signature, signature_element)
        signature.signed_info.references.map do |ref|
          verify_reference(ref, signature_element)
        end
      end

      def verify_reference(reference, signature_element)
        resolver = ReferenceResolver.new(context: context, document: document)
        input = resolver.resolve(reference.uri)
        pipeline = TransformPipeline.new(
          context: context,
          signature_element: signature_element,
        )
        transformed = pipeline.apply(input, reference.transforms)
        canonical = pipeline.to_octets(transformed, reference)

        digest_algo = Algorithms.lookup(
          :digest, reference.digest_method.algorithm
        ).new
        computed = digest_algo.digest_base64(canonical)
        expected = (reference.digest_value || "").strip

        ReferenceResult.new(
          uri: reference.uri,
          digest_method: reference.digest_method.algorithm,
          expected: expected,
          computed: computed,
        )
      end
    end
  end
end
