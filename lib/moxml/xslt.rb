# frozen_string_literal: true

module Moxml
  # XSLT transformation. Implementation-agnostic over engines that
  # ship an XSLT processor (currently nokogiri/libxslt and leptris;
  # leptris additionally covers XSLT 2.0/3.0 per its engine).
  #
  #     ctx    = Moxml.new(:nokogiri)
  #     sheet  = ctx.xslt(<<~XSL)
  #       <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  #         <xsl:template match="/"><out><xsl:value-of select="count(//i)"/></out></xsl:template>
  #       </xsl:stylesheet>
  #     XSL
  #     sheet.apply_to(doc)          # => Moxml::Document (same adapter)
  #     sheet.apply_to_string(doc)   # => String (engine-serialized output;
  #                                  #    fragments and text output preserved)
  #
  # Adapters without an engine raise Moxml::NotImplementedError at
  # compile; Moxml::XSLT.supported?(context) answers without raising.
  #
  # Stylesheet top-level parameters are part of the contract but not
  # every engine threads them yet — passing non-empty params to an
  # engine without the face raises Moxml::XsltError (leptris:
  # leptris-ruby#360).
  module XSLT
    autoload :Stylesheet, "moxml/xslt/stylesheet"

    SUPPORTED_ADAPTERS = %i[nokogiri leptris].freeze

    class << self
      # Whether the context's adapter ships an XSLT engine. Answers
      # without raising; compile raises Moxml::NotImplementedError
      # regardless (the capability probe is advisory).
      def supported?(context)
        adapter = context.config.adapter
        adapter.const_defined?(:XSLT_SUPPORTED) &&
          adapter.const_get(:XSLT_SUPPORTED)
      end

      # Quote XSLT top-level string parameters into the flat
      # name/value list libxslt-family engines accept. Values are
      # single-quoted; embedded quotes are escaped.
      def quote_params(params)
        params.flat_map do |name, value|
          quoted = "'#{value.to_s.gsub("'", %q{'\''})}'"
          [name.to_s, quoted]
        end
      end
    end
  end
end
