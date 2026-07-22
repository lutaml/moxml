# frozen_string_literal: true

require "forwardable"

module Moxml
  module Signature
    # Core Validation per spec §3.2, with the safe ordering prescribed by
    # Best Practice 1: verify SignatureValue BEFORE running any reference
    # transforms (which could be hostile).
    class Verifier
      attr_reader :context, :document, :key

      def initialize(context:, document:, key:, **_options)
        @context = context
        @document = document
        @key = key
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
        signature_value_ok = verify_signature_value(signature)
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

      def verify_signature_value(signature)
        return false if signature.signature_value.nil?
        return false if signature.signature_value.value.nil?

        signed_info_doc = Serializer.new(context: context)
          .serialize_signed_info(signature.signed_info)

        c14n_uri = signature.signed_info.canonicalization_method&.algorithm
        return false if c14n_uri.nil?

        c14n = Algorithms.lookup(:canonicalization, c14n_uri)
          .new(identifier_uri: c14n_uri)
        canonical = c14n.canonicalize(signed_info_doc.root)

        sm_uri = signature.signed_info.signature_method.algorithm
        sm = Algorithms.lookup(:signature_method, sm_uri)
          .new(
            identifier_uri: sm_uri,
            parameters: signature.signed_info.signature_method.parameters,
          )
        sm.verify(canonical, key, signature.signature_value.value)
      rescue VerificationError
        false
      end

      def verify_references(signature, signature_element)
        signature.signed_info.references.map do |ref|
          verify_reference(ref, signature_element)
        end
      end

      def verify_reference(reference, signature_element)
        resolver = ReferenceResolver.new(context: context, document: document)
        input = resolver.resolve(reference.uri)
        input = apply_transforms(input, reference, signature_element: signature_element)
        canonical = nodeset_to_octets(input, reference)

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

      def apply_transforms(input, reference, signature_element:)
        current = input
        current_type = type_of(current)
        (reference.transforms&.transforms || []).each do |t|
          algo_class = lookup_transform(t.algorithm)
          transform = algo_class.new(
            parameters: t.parameters,
            context: context,
            signature_element: signature_element,
          )
          new_type, coerced = coerce_type(current, current_type,
                                          algo_class.input_type)
          current_type = new_type
          current = transform.transform(coerced)
          current_type = algo_class.output_type
        end
        current
      end

      def lookup_transform(uri)
        Algorithms.lookup(:transform, uri)
      rescue UnknownAlgorithm
        Algorithms.lookup(:canonicalization, uri)
      end

      def coerce_type(input, from, to)
        return [to, input] if from == to

        case [from, to]
        when %i[octets nodeset]
          parsed = context.parse(input.to_s)
          [:nodeset, parsed.root]
        when %i[nodeset octets]
          octets = C14n::Inclusive10.new.canonicalize(input)
          [:octets, octets]
        else
          raise TransformError, "cannot coerce #{from} to #{to}"
        end
      end

      def type_of(value)
        case value
        when ::Moxml::Node, Array then :nodeset
        else :octets
        end
      end

      def nodeset_to_octets(value, reference)
        return value if value.is_a?(String)

        # Prefer the last canonicalization transform in the reference if any,
        # else fall back to the SignedInfo's canonicalization method.
        c14n_uri = canonicalization_from_transforms(reference) ||
          signature_signed_info_c14n(reference)
        klass = Algorithms.lookup(:canonicalization, c14n_uri)
        klass.new(identifier_uri: c14n_uri).canonicalize(value)
      end

      def canonicalization_from_transforms(reference)
        return nil unless reference.transforms

        reference.transforms.transforms.reverse_each.find do |t|
          Algorithms.registered?(:canonicalization, t.algorithm)
        end&.algorithm
      end

      def signature_signed_info_c14n(_reference)
        # We don't have direct access to SignedInfo here; default to exc-c14n.
        "http://www.w3.org/2001/10/xml-exc-c14n#"
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
