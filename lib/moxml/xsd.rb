# frozen_string_literal: true

module Moxml
  # XSD validation. Implementation-agnostic over engines that ship
  # an XSD validator (currently leptris, tier-1: named+typed
  # top-level elements, one-level content-model descent, lexical
  # builtin/simpleType checks — see docs/c14n for the sibling
  # pattern).
  #
  #     ctx    = Moxml.new(:leptris)
  #     schema = ctx.xsd(<<~XSD)
  #       <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
  #         <xs:element name="note" type="t_note"/>
  #         <xs:complexType name="t_note">
  #           <xs:sequence>
  #             <xs:element name="to" type="xs:string"/>
  #           </xs:sequence>
  #         </xs:complexType>
  #       </xs:schema>
  #     XSD
  #     schema.valid?(doc)     # => true/false
  #     schema.validate(doc)   # => [] or ["1:0: ...", ...]
  #
  # Adapters without an engine raise Moxml::NotImplementedError at
  # compile; Moxml::XSD.supported?(context) answers without
  # raising. The tier-1 scope is the engine's: documents outside it
  # validate laxly (see the binding's xsd_validate_spec).
  module XSD
    SUPPORTED_ADAPTERS = %i[leptris].freeze

    class << self
      # Whether the context's adapter ships an XSD validator.
      # Answers without raising; compile raises
      # Moxml::NotImplementedError regardless (the capability probe
      # is advisory).
      def supported?(context)
        adapter = context.config.adapter
        adapter.const_defined?(:XSD_SUPPORTED) &&
          adapter.const_get(:XSD_SUPPORTED)
      end

      # Lexical validation against the built-in type table (the
      # "xs:NAME" reference spelling). Raises ArgumentError when the
      # name is not in the table; NotImplementedError on adapters
      # without an engine.
      def builtin_valid?(context, builtin, lexical)
        context.config.adapter.xsd_builtin_valid?(builtin, lexical)
      end
    end

    # A compiled schema (adapter-owned handle). Validation results
    # are the engine's accumulated messages; [] means valid.
    class Schema
      def initialize(handle, context)
        @handle = handle
        @context = context
      end

      # Validate a node or raw XML string. Returns [] when valid.
      # FROZEN string sources parse once and are memoized for the
      # schema's lifetime — re-validating the same document is the
      # hot consumer shape, and a per-call parse costs the full
      # document pool every time (moxml#350's MB-per-validate
      # growth). Unfrozen strings re-parse (mutation must be
      # visible); pass a Moxml::Document to control the parse
      # yourself.
      def validate(node_or_xml)
        doc = case node_or_xml
              when Moxml::Document then node_or_xml
              when Moxml::Node then node_or_xml.document
              else
                cached = @parsed_source
                if cached && node_or_xml.frozen? &&
                    cached[0].equal?(node_or_xml)
                  cached[1]
                else
                  parsed = @context.parse(node_or_xml.to_s)
                  if node_or_xml.frozen?
                    @parsed_source = [node_or_xml, parsed]
                  end
                  parsed
                end
              end
        @context.config.adapter.xsd_validate(@handle, doc.native)
      end

      def valid?(node_or_xml)
        validate(node_or_xml).empty?
      end

      # Number of top-level schema declarations the compiler
      # recognized.
      def declarations
        @context.config.adapter.xsd_declarations(@handle)
      end

      # The engine's schema-level compile error, or nil when the
      # schema compiled cleanly.
      def compile_error
        @context.config.adapter.xsd_compile_error(@handle)
      end

      # Lexical validation of +lexical+ against the schema's user
      # simpleType +type_name+. Unknown type names raise.
      def simple_valid?(type_name, lexical)
        @context.config.adapter.xsd_simple_valid?(
          @handle, type_name, lexical
        )
      end

      # Content-model check for one element's children. +children+
      # are Moxml nodes (names + effective namespaces are read
      # engine-side). Unknown element names raise.
      def content_valid?(element_name, children)
        @context.config.adapter.xsd_content_valid?(
          @handle, element_name, children
        )
      end
    end
  end
end
