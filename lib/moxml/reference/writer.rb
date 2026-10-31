# frozen_string_literal: true

module Moxml
  module Reference
    # Pure-Ruby serializers for the model's three shapes. The XML
    # writer is the reference for the facade's canonical output at
    # indent: 0; the HTML/XHTML writers pin the shape contracts (void
    # elements unclosed vs self-closed, raw text nodes, no XML
    # declaration).
    #
    # Output is assembled as an array of parts and joined: the
    # reference stays off mutable String#<< by design (cheap total
    # behavior, no per-call buffer semantics).
    class Writer
      VOID_ELEMENTS = %w[
        area base br col embed hr img input link meta param source
        track wbr
      ].freeze
      RAW_TEXT_ELEMENTS = %w[script style].freeze

      TEXT_ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze
      ATTRIBUTE_ESCAPES = TEXT_ESCAPES.merge('"' => "&quot;").freeze
      TEXT_ESCAPE_RE = /[&<>]/
      ATTRIBUTE_ESCAPE_RE = /[&<>"]/
      CDATA_END = "]]>"
      CDATA_SPLIT = "]]]]><![CDATA[>"

      def initialize(document)
        @document = document
      end

      def to_xml
        emit(:xml)
      end

      def to_html
        emit(:html)
      end

      def to_xhtml
        emit(:xhtml)
      end

      private

      def emit(shape)
        parts = []
        parts << declaration if shape == :xml && @document.declaration
        @document.children.each { |node| write(node, parts, shape) }
        parts.join
      end

      def declaration
        source = @document.declaration
        attributes = []
        attributes << %(version="#{escape_attribute(source[:version])}") if source[:version]
        attributes << %(encoding="#{escape_attribute(source[:encoding])}") if source[:encoding]
        attributes << %(standalone="#{escape_attribute(source[:standalone])}") if source[:standalone]
        "<?xml #{attributes.join(' ')}?>"
      end

      def write(node, parts, shape)
        case node.kind
        when :element then write_element(node, parts, shape)
        when :text then write_text(node, parts, shape)
        when :comment then parts << "<!--#{node.data}-->"
        when :cdata then parts << cdata(node.data)
        when :processing_instruction then write_pi(node, parts)
        end
      end

      def write_element(node, parts, shape)
        parts << "<" << node.name
        node.attributes.each do |(name, value)|
          parts << " " << name << '="' << escape_attribute(value) << '"'
        end

        if shape == :html && VOID_ELEMENTS.include?(node.name)
          parts << ">"
        elsif shape == :xhtml && VOID_ELEMENTS.include?(node.name)
          parts << "/>"
        elsif node.children.empty?
          if shape == :xml
            parts << "/>"
          else
            parts << "></" << node.name << ">"
          end
        else
          parts << ">"
          node.children.each { |child| write(child, parts, shape) }
          parts << "</" << node.name << ">"
        end
      end

      def write_text(node, parts, shape)
        parent = node.parent
        raw = shape != :xhtml && parent &&
          RAW_TEXT_ELEMENTS.include?(parent.name)
        parts << (raw ? node.data : escape_text(node.data))
      end

      def write_pi(node, parts)
        parts << "<?" << node.name
        parts << " " << node.data unless node.data.nil? || node.data.empty?
        parts << "?>"
      end

      def cdata(data)
        "<![CDATA[#{data.gsub(CDATA_END, CDATA_SPLIT)}]]>"
      end

      def escape_text(text)
        text.to_s.gsub(TEXT_ESCAPE_RE, TEXT_ESCAPES)
      end

      def escape_attribute(value)
        value.to_s.gsub(ATTRIBUTE_ESCAPE_RE, ATTRIBUTE_ESCAPES)
      end
    end
  end
end
