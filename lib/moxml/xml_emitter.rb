# frozen_string_literal: true

module Moxml
  # Single source of XML emission knowledge: character escaping,
  # CDATA end-sequence segmentation, and declaration/DOCTYPE
  # rendering. Adapters keep their tree walks (those are
  # adapter-shaped) but stop re-deriving the wire format:
  #
  # - text escapes & < >; attribute values also escape " —
  #   apostrophes stay literal (moxml-canonical form)
  # - a CDATA section's end sequence is split into adjacent sections
  # - the moxml declaration shape is <?xml version="..."
  #   encoding="..." standalone="..."?> with only the set attributes
  # - DOCTYPE renders PUBLIC and SYSTEM external identifiers
  module XmlEmitter
    TEXT_ESCAPE_RE = /[<>&]/
    TEXT_ESCAPE_MAP = {
      "<" => "&lt;", ">" => "&gt;", "&" => "&amp;"
    }.freeze
    ATTRIBUTE_ESCAPE_RE = /[<>&"]/
    ATTRIBUTE_ESCAPE_MAP = {
      "<" => "&lt;", ">" => "&gt;", "&" => "&amp;", '"' => "&quot;"
    }.freeze
    CDATA_END = "]]>"
    CDATA_END_SPLIT = "]]]]><![CDATA[>"

    module_function

    # @return [String] text with & < > escaped
    def escape_text(text)
      str = text.is_a?(String) ? text : text.to_s
      return str unless str.match?(TEXT_ESCAPE_RE)

      str.gsub(TEXT_ESCAPE_RE, TEXT_ESCAPE_MAP)
    end

    # @return [String] attribute value with & < > " escaped
    def escape_attribute(value)
      str = value.is_a?(String) ? value : value.to_s
      return str unless str.match?(ATTRIBUTE_ESCAPE_RE)

      str.gsub(ATTRIBUTE_ESCAPE_RE, ATTRIBUTE_ESCAPE_MAP)
    end

    # @return [String] a CDATA section, splitting any embedded end
    #   sequence into adjacent sections
    def cdata(content)
      "<![CDATA[#{content.to_s.gsub(CDATA_END, CDATA_END_SPLIT)}]]>"
    end

    # @return [String] an XML declaration with only the set attributes
    def declaration_xml(version, encoding, standalone)
      output = %(<?xml version="#{version}")
      output << %( encoding="#{encoding}") if encoding && !encoding.to_s.empty?
      output << %( standalone="#{standalone}") unless standalone.nil?
      output << "?>"
    end

    # @return [String] a DOCTYPE with its external identifier
    def doctype_xml(name, public_id, system_id)
      output = "<!DOCTYPE #{name}"
      if public_id && !public_id.to_s.empty?
        output << %( PUBLIC "#{public_id}")
        output << %( "#{system_id}") if system_id
      elsif system_id && !system_id.to_s.empty?
        output << %( SYSTEM "#{system_id}")
      end
      output << ">"
    end
  end
end
