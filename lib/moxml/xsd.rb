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
  #     schema.validate(doc)   # => [] or [ValidationError(...)]
  #
  # Adapters without an engine raise Moxml::NotImplementedError at
  # compile; Moxml::XSD.supported?(context) answers without
  # raising. The tier-1 scope is the engine's: documents outside it
  # validate laxly (see the binding's xsd_validate_spec).
  module XSD
    SUPPORTED_ADAPTERS = %i[leptris nokogiri].freeze

    # One validation finding, harmonized across adapters (#362.2):
    # +message+ always present; +line+ / +column+ when the engine
    # reports them; +path+ (the element path) when the engine
    # reports it — nil where the payload lacks the datum rather
    # than a guessed placeholder. #to_s preserves the plain-string
    # consumer flows the pre-#362 string contract fed.
    class ValidationError
      attr_reader :message, :line, :column, :path

      def initialize(message:, line: nil, column: nil, path: nil)
        @message = message.to_s
        @line = line
        @column = column
        @path = path
      end

      def to_s
        if line
          "#{line}: #{message}"
        else
          message
        end
      end

      def ==(other)
        other.is_a?(ValidationError) &&
          message == other.message && line == other.line &&
          column == other.column && path == other.path
      end
    end

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
      def check_released!
        return unless released?

        raise Moxml::AdapterError,
              "schema released (deterministic drop); compile a new one"
      end

      def initialize(handle, context)
        @handle = handle
        @context = context
        assert_adapter_matches_handle!
      end

      # Issue #384: the handle is an adapter-native object; routing
      # it through a different adapter's xsd_validate surfaced as a
      # distant NoMethodError. Fail at the wrap with the mismatch
      # named.
      def assert_adapter_matches_handle!
        adapter = @context.config.adapter
        return if adapter.xsd_handle_match?(@handle)

        raise Moxml::AdapterError.new(
          "schema handle mismatch: #{handle_class_name(@handle)} " \
          "cannot be validated through the " \
          "#{adapter.respond_to?(:adapter_name) ? adapter.adapter_name : adapter} " \
          "adapter — compile the schema through the same adapter " \
          "that will validate it",
          operation: "xsd_compile",
        )
      end

      def handle_class_name(handle)
        handle.class.name.split("::").last(2).join("::")
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
        check_released!
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
        check_released!
        validate(node_or_xml).empty?
      end

      # Number of top-level schema declarations the compiler
      # recognized.
      def declarations
        check_released!
        @context.config.adapter.xsd_declarations(@handle)
      end

      # Deterministic drop (#362.3): true when the adapter freed
      # the engine-side schema NOW; false when the adapter can only
      # wait for GC (documented per adapter). After a true release
      # the faces raise AdapterError — the handle is gone.
      def release
        dropped = @context.config.adapter.xsd_release(@handle)
        @released = true if dropped
        dropped
      end

      def released?
        @released == true
      end

      # The engine's schema-level compile error, or nil when the
      # schema compiled cleanly.
      def compile_error
        check_released!
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
