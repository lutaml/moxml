# frozen_string_literal: true

module Moxml
  module Signature
    # Shared transform-pipeline logic used by both Signer (signing flow,
    # signature_element: nil) and Verifier (verification flow, with the
    # containing Signature element so the Enveloped Signature transform
    # can remove it from the digest input).
    #
    # Each Transform in the chain is looked up via Algorithms.lookup(:transform, uri),
    # with a fallback to Algorithms.lookup(:canonicalization, uri) per
    # spec §6.6.1 (any canonicalization algorithm can be used as a transform).
    #
    # Type coercion matches spec §4.4.3.2 reference processing model:
    #   - octets → nodeset: parse as XML
    #   - nodeset → octets: apply inclusive C14N 1.0
    class TransformPipeline
      attr_reader :context, :signature_element

      def initialize(context:, signature_element: nil)
        @context = context
        @signature_element = signature_element
      end

      def apply(input, transforms_model)
        current = input
        current_type = type_of(current)
        transforms = transforms_from(transforms_model)

        transforms.each do |transform_model|
          algo_class = lookup(transform_model.algorithm)
          transform = algo_class.new(
            parameters: transform_model.parameters,
            context: context,
            signature_element: signature_element,
          )
          current_type, current = coerce(current, current_type,
                                         algo_class.input_type)
          current = transform.transform(current)
          current_type = algo_class.output_type
        end

        current
      end

      # Final step: convert the pipeline output (which may still be a node)
      # to octets suitable for digesting. Uses inclusive C14N 1.0 as the
      # default mapping per spec §4.4.3.2.
      def to_octets(value, reference = nil)
        return value if value.is_a?(String)

        c14n_uri = canonicalization_from(reference) || DEFAULT_OCTET_C14N
        klass = Algorithms.lookup(:canonicalization, c14n_uri)
        klass.new(identifier_uri: c14n_uri).canonicalize(value)
      end

      DEFAULT_OCTET_C14N = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"

      private_constant :DEFAULT_OCTET_C14N

      private

      def transforms_from(transforms_model)
        return [] unless transforms_model

        transforms_model.transforms
      end

      def lookup(uri)
        Algorithms.lookup(:transform, uri)
      rescue UnknownAlgorithm
        Algorithms.lookup(:canonicalization, uri)
      end

      def type_of(value)
        case value
        when ::Moxml::Node, Array then :nodeset
        else :octets
        end
      end

      def coerce(input, from, to)
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

      def canonicalization_from(reference)
        return nil unless reference&.transforms

        reference.transforms.transforms.reverse_each.find do |t|
          Algorithms.registered?(:canonicalization, t.algorithm)
        end&.algorithm
      end
    end
  end
end
