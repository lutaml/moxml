# frozen_string_literal: true

require "forwardable"

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
        Result.new(results: results)
      end

      private

      def find_signatures
        document.xpath("//ds:Signature", "ds" => DSIG_NS)
          .grep(::Moxml::Element)
      end

      def verify_one(signature_element)
        signature = Parser.new(context: context).parse(signature_element)
        signature_value_ok = verify_signature_value(signature, signature_element)
        reference_results = if signature_value_ok
                              verify_references(signature, signature_element)
                            else
                              []
                            end

        SingleResult.new(
          signature_id: signature.id,
          signature_valid: signature_value_ok,
          references: reference_results,
        )
      end

      def verify_signature_value(signature, signature_element)
        return false if signature.signature_value.nil?
        return false if signature.signature_value.value.nil?

        # Canonicalize the original SignedInfo element as it appears in the
        # document — re-serializing the parsed model would change prefixes
        # (e.g., default-namespace SignedInfo → ds:SignedInfo), breaking
        # the byte-exact match the signature was computed against.
        signed_info_elem = signature_element.at_xpath(
          "./ds:SignedInfo", "ds" => DSIG_NS
        )
        return false if signed_info_elem.nil?

        c14n_uri = signature.signed_info.canonicalization_method&.algorithm
        return false if c14n_uri.nil?

        c14n = Algorithms.lookup(:canonicalization, c14n_uri)
          .new(identifier_uri: c14n_uri)
        canonical = c14n.canonicalize(signed_info_elem)

        sm_uri = signature.signed_info.signature_method.algorithm
        sm = Algorithms.lookup(:signature_method, sm_uri)
          .new(
            identifier_uri: sm_uri,
            parameters: signature.signed_info.signature_method.parameters,
          )
        verification_key = resolve_key(signature)
        return false if verification_key.nil?

        sm.verify(canonical, verification_key, signature.signature_value.value)
      rescue VerificationError
        false
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

      def canonicalization_from_transforms(reference)
        return nil unless reference.transforms

        reference.transforms.transforms.reverse_each.find do |t|
          Algorithms.registered?(:canonicalization, t.algorithm)
        end&.algorithm
      end
    end

    # Aggregated verification result for a document (may contain multiple
    # signatures).
    class Result
      attr_reader :results

      def initialize(results:)
        @results = results
      end

      def valid?
        results.all?(&:valid?)
      end

      def signature_count
        results.size
      end
    end

    class SingleResult
      attr_reader :signature_id, :references

      def initialize(signature_id:, signature_valid:, references:)
        @signature_id = signature_id
        @signature_valid = signature_valid
        @references = references
      end

      def signature_valid?
        @signature_valid
      end

      def valid?
        @signature_valid && references.all?(&:valid?)
      end
    end

    class ReferenceResult
      attr_reader :uri, :digest_method, :expected, :computed

      def initialize(uri:, digest_method:, expected:, computed:)
        @uri = uri
        @digest_method = digest_method
        @expected = expected
        @computed = computed
      end

      def valid?
        expected == computed
      end
    end
  end
end
