# frozen_string_literal: true

module Moxml
  module Signature
    module Algorithms
      # Base class for XML Signature transforms.
      #
      # Each transform declares input and output types (:octets or :nodeset)
      # plus an identifier URI. The reference resolver chains them with
      # default type conversion when types mismatch (octets → nodeset via
      # XML parse; nodeset → octets via inclusive C14N 1.0).
      class TransformBase
        class << self
          attr_reader :identifier_uri

          def identifier(uri)
            @identifier_uri = uri
            Algorithms.register(:transform, uri, self)
          end

          def input_type; :octets; end
          def output_type; :octets; end
        end

        # `parameters`: optional hash parsed from the ds:Transform element
        # (e.g. { xpaths: [...] } for the XPath Filter transform).
        def initialize(parameters: nil, context: nil, signature_element: nil)
          @parameters = parameters || {}
          @context = context
          @signature_element = signature_element
        end

        def transform(_input)
          raise NotImplementedError,
                "#{self.class} must implement #transform"
        end
      end
    end
  end
end
