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
        input = apply_transforms(input, reference, signature_element: nil)
        canonical = nodeset_to_octets(input)
        digest_algo = Algorithms.lookup(:digest, reference.digest_method.algorithm).new
        digest_algo.digest_base64(canonical)
      end

      def apply_transforms(input, reference, signature_element:)
        current = input
        current_type = type_of(current)
        reference.transforms&.each do |t|
          algo_class = lookup_transform(t.algorithm)
          transform = algo_class.new(
            parameters: t.parameters,
            context: context,
            signature_element: signature_element,
          )
          current_type, current = coerce_type(current, current_type,
                                              transform.class.input_type)
          current = transform.transform(current)
          current_type = transform.class.output_type
        end
        current
      end

      def lookup_transform(uri)
        Algorithms.lookup(:transform, uri)
      rescue UnknownAlgorithm
        # Canonicalization algorithms are also valid transforms per spec §6.6.1
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

      def nodeset_to_octets(value)
        return value if value.is_a?(String)

        # Default behavior: canonicalize the node-set using the first
        # canonicalization algorithm declared in the SignedInfo (or exc-c14n
        # if none). The proper behavior per spec §3.1.1 is to apply C14N
        # only when the next transform requires octets; here we apply it as
        # the implicit final step before digesting.
        c14n = canonicalization_for_digest(signature.signed_info)
        c14n.canonicalize(value)
      end

      def canonicalization_for_digest(signed_info)
        uri = signed_info.canonicalization_method&.algorithm ||
          "http://www.w3.org/2001/10/xml-exc-c14n#"
        klass = Algorithms.lookup(:canonicalization, uri)
        klass.new(identifier_uri: uri)
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
