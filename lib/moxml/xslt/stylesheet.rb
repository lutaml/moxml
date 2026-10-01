# frozen_string_literal: true

module Moxml
  module XSLT
    # A compiled stylesheet bound to one adapter context. Apply to
    # documents parsed by the same adapter; cross-adapter documents
    # take the serialized path (to_xml -> engine -> parse).
    class Stylesheet
      # @api adapter — the engine's compiled stylesheet handle
      attr_reader :native

      def initialize(native_sheet, context)
        @native = native_sheet
        @context = context
        @adapter = context.config.adapter
      end

      # Transform +document+ and return the result as a
      # Moxml::Document of this stylesheet's adapter.
      #
      # Stylesheets whose output method is not XML raise
      # Moxml::XsltError — the serialized form is available through
      # apply_to_string.
      #
      # @param params [Hash] top-level stylesheet parameters
      #   (name => string value); engines without a params face
      #   raise Moxml::XsltError when non-empty
      def apply_to(document, params: {})
        quoted = quote_params(params)
        return apply_cross_adapter(document, quoted) unless same_adapter?(document)

        result = @adapter.xslt_apply_document(@native, document.native, quoted)
        return parse_serialized(document, quoted) if result.nil?

        wrapped = Wrappers::Document.new(result, @context)
        # Engines differ on non-XML output: leptris returns nil, nokogiri
        # wraps the text into a rootless document. Normalize to a typed
        # error — apply_to_string carries non-XML output.
        raise XsltError, non_xml_message if wrapped.root.nil?

        wrapped
      end

      # Transform +document+ and return the engine-serialized output.
      # Preserves result fragments and text output that the document
      # face cannot represent.
      def apply_to_string(document, params: {})
        quoted = quote_params(params)
        return apply_cross_adapter_string(document, quoted) unless same_adapter?(document)

        @adapter.xslt_apply_string(@native, document.native, quoted)
      end

      private

      def same_adapter?(document)
        document.context.config.adapter.equal?(@adapter)
      end

      # Cross-adapter documents serialize through their own adapter
      # and re-parse into the stylesheet's engine — the engine cannot
      # share its tree across adapters.
      def apply_cross_adapter(document, quoted)
        engine_doc = @context.parse(document.to_xml)
        result = @adapter.xslt_apply_document(@native, engine_doc.native, quoted)
        return parse_serialized(engine_doc, quoted) if result.nil?

        Wrappers::Document.new(result, @context)
      end

      def apply_cross_adapter_string(document, quoted)
        engine_doc = @context.parse(document.to_xml)
        @adapter.xslt_apply_string(@native, engine_doc.native, quoted)
      end

      def parse_serialized(document, quoted)
        @context.parse(@adapter.xslt_apply_string(@native, document.native, quoted))
      rescue Moxml::ParseError
        raise XsltError, non_xml_message
      end

      def non_xml_message
        "transform output is not XML (output method text?); use apply_to_string"
      end

      def quote_params(params)
        return [] if params.nil? || params.empty?

        XSLT.quote_params(params)
      end
    end
  end
end
