# frozen_string_literal: true

module Moxml
  module Reference
    # A small, total XML reader for the model's input taxonomy. No
    # recovery: malformed input raises a named ParseError. The only
    # dependencies are Ruby's String and Regexp alone.
    class Parser
      NAME = /[A-Za-z_:][-A-Za-z0-9_:.]*/
      XML_WHITESPACE = /[ \t\n\r]/
      ATTRIBUTE_LITERAL_WHITESPACE = /[\t\n\r]/
      BUILTIN_ENTITIES = {
        "amp" => "&", "lt" => "<", "gt" => ">",
        "quot" => '"', "apos" => "'"
      }.freeze
      BOM = "\xEF\xBB\xBF"
      QUOTES = ['"', "'"].freeze
      DECLARATION_OPEN_SIZE = 5
      DOCTYPE_OPEN_SIZE = 9
      COMMENT_OPEN_SIZE = 4
      COMMENT_CLOSE_SIZE = 3
      CDATA_OPEN_SIZE = 9
      CDATA_CLOSE_SIZE = 3
      PI_OPEN_SIZE = 2
      PI_CLOSE_SIZE = 2

      def initialize(xml)
        @source = ""
        @pos = 0
        @source = prepare_source(xml)
        @length = @source.length
        @entities = BUILTIN_ENTITIES.dup
      end

      def parse
        document = Document.new
        parse_prolog(document)
        raise error("no root element") if at_end?

        document.children << parse_element(nil)
        parse_epilog(document)
        document.entities = @entities
        document
      end

      private

      def prepare_source(xml)
        source = xml.to_s
        source = source.encode(Encoding::UTF_8) unless source.encoding == Encoding::UTF_8
        raise error("source is not valid UTF-8") unless source.valid_encoding?

        source = source.delete_prefix(BOM)
        # XML 1.0 §2.11: literal CRLF and CR normalize to LF. Character
        # references are expanded later and keep their value.
        source.gsub("\r\n", "\n").gsub("\r", "\n")
      rescue EncodingError => e
        raise error("source cannot be read as UTF-8: #{e.message}")
      end

      def parse_prolog(document)
        loop do
          skip_whitespace
          if declaration_start?
            if document.children.empty? && document.declaration.nil?
              document.declaration = parse_declaration
            else
              raise error("XML declaration is not first")
            end
          elsif start_with?("<!--")
            document.children << parse_comment
          elsif start_with?("<?")
            document.children << parse_processing_instruction
          elsif start_with?("<!DOCTYPE")
            document.doctype = parse_doctype
          else
            return
          end
        end
      end

      def parse_epilog(document)
        loop do
          skip_whitespace
          return if at_end?

          if start_with?("<!--")
            document.children << parse_comment
          elsif start_with?("<?")
            document.children << parse_processing_instruction
          else
            raise error("content after the root element")
          end
        end
      end

      def declaration_start?
        return false unless start_with?("<?xml")

        following = @source[@pos + 5]
        following.nil? || following == "?" || XML_WHITESPACE.match?(following)
      end

      def parse_declaration
        start = @pos
        @pos += DECLARATION_OPEN_SIZE
        attributes = parse_attributes_until("?>").to_h
        {
          version: attributes["version"],
          encoding: attributes["encoding"],
          standalone: attributes["standalone"],
          raw: @source[start...@pos],
        }
      end

      def parse_doctype
        start = @pos
        @pos += DOCTYPE_OPEN_SIZE
        depth = 0
        quote = nil
        until at_end?
          char = @source[@pos]
          if quote
            quote = nil if char == quote
          elsif QUOTES.include?(char)
            quote = char
          elsif char == "["
            depth += 1
          elsif char == "]"
            depth -= 1
          elsif char == ">" && depth.zero?
            @pos += 1
            raw = @source[start...@pos]
            collect_entities(raw)
            return raw
          end
          @pos += 1
        end
        raise error("unterminated DOCTYPE")
      end

      def collect_entities(raw)
        raw.scan(/<!ENTITY\s+([^\s%][^\s]*)\s+(?:"([^"]*)"|'([^']*)')/) do |name, dq, sq|
          @entities[name] = dq || sq
        end
      end

      def parse_element(parent, scope = {})
        expect("<")
        name = scan_name || raise(error("element name expected"))
        attributes = parse_attributes_until(">", allow_empty_close: true)
        node = Node.new(kind: :element, name: name, attributes: attributes)
        node.parent = parent

        element_scope = extend_scope(scope, attributes)
        validate_prefixes(name, attributes, element_scope)

        # parse_attributes_until consumed either ">" or "/>".
        return node if @pos >= 2 && @source[@pos - 2, 2] == "/>"

        parse_element_content(node, element_scope)
        node
      end

      # Namespace bindings are parser state: xmlns declarations extend
      # the in-scope table for the element and its descendants.
      def extend_scope(scope, attributes)
        extended = nil
        attributes.each do |(name, value)|
          if name == "xmlns"
            (extended ||= scope.dup)[""] = value
          elsif name.start_with?("xmlns:")
            (extended ||= scope.dup)[name.delete_prefix("xmlns:")] = value
          end
        end
        extended || scope
      end

      def validate_prefixes(name, attributes, scope)
        check_prefix(name, scope, "element")
        attributes.each do |(attribute_name, _)|
          next if attribute_name == "xmlns" ||
            attribute_name.start_with?("xmlns:")

          check_prefix(attribute_name, scope, "attribute")
        end
      end

      def check_prefix(name, scope, kind)
        return unless name.include?(":")

        prefix = name.split(":", 2).first
        return if prefix == "xml"

        return if scope.key?(prefix)

        raise error("undeclared namespace prefix #{prefix.inspect} on #{kind} #{name}")
      end

      def parse_element_content(node, scope)
        loop do
          raise error("unclosed element <#{node.name}>") if at_end?

          if start_with?("</")
            @pos += 2
            close_name = scan_name
            skip_whitespace
            expect(">")
            unless close_name == node.name
              raise error("mismatched closing tag </#{close_name}> for <#{node.name}>")
            end

            return

          elsif start_with?("<!--")
            node.children << parse_comment(node)
          elsif start_with?("<![CDATA[")
            node.children << parse_cdata(node)
          elsif start_with?("<?")
            node.children << parse_processing_instruction(node)
          elsif start_with?("<")
            node.children << parse_element(node, scope)
          else
            text = parse_text(node)
            node.children << text if text
          end
        end
      end

      def parse_text(parent = nil)
        stop = @source.index("<", @pos)
        stop ||= @length
        raw = @source[@pos...stop]
        @pos = stop
        return if raw.empty?

        node = Node.new(kind: :text, data: expand_entities(raw))
        node.parent = parent
        node
      end

      def parse_comment(parent = nil)
        @pos += COMMENT_OPEN_SIZE
        stop = @source.index("-->", @pos)
        raise error("unterminated comment") unless stop

        data = @source[@pos...stop]
        @pos = stop + COMMENT_CLOSE_SIZE
        node = Node.new(kind: :comment, data: data)
        node.parent = parent
        node
      end

      def parse_cdata(parent = nil)
        @pos += CDATA_OPEN_SIZE
        stop = @source.index("]]>", @pos)
        raise error("unterminated CDATA section") unless stop

        data = @source[@pos...stop]
        @pos = stop + CDATA_CLOSE_SIZE
        node = Node.new(kind: :cdata, data: data)
        node.parent = parent
        node
      end

      def parse_processing_instruction(parent = nil)
        @pos += PI_OPEN_SIZE
        target = scan_name || raise(error("PI target expected"))
        stop = @source.index("?>", @pos)
        raise error("unterminated processing instruction") unless stop

        data = @source[@pos...stop]
        @pos = stop + PI_CLOSE_SIZE
        # The separating whitespace after the target is parser syntax,
        # not data (model, Access semantics).
        data = data.sub(/\A[ \t\n\r]+/, "")
        node = Node.new(kind: :processing_instruction, name: target, data: data)
        node.parent = parent
        node
      end

      # Parses attributes until the terminator. With allow_empty_close,
      # a "/>" terminator is consumed and leaves the position after
      # it; otherwise the exact terminator is expected.
      def parse_attributes_until(terminator, allow_empty_close: false)
        attributes = []
        seen = {}
        loop do
          skip_whitespace
          if allow_empty_close && start_with?("/>")
            @pos += 2
            return attributes
          end
          if start_with?(terminator)
            @pos += terminator.length
            return attributes
          end
          raise error("attribute or #{terminator} expected") if at_end?

          name = scan_name || raise(error("attribute name expected"))
          skip_whitespace
          expect("=")
          skip_whitespace
          value = scan_attribute_value
          raise error("duplicate attribute #{name}") if seen[name]

          seen[name] = true
          attributes << [name, value]
        end
      end

      def scan_attribute_value
        quote = @source[@pos]
        raise error("quoted attribute value expected") unless QUOTES.include?(quote)

        @pos += 1
        stop = @source.index(quote, @pos)
        raise error("unterminated attribute value") unless stop

        raw = @source[@pos...stop]
        @pos = stop + 1
        expand_entities(raw.gsub(ATTRIBUTE_LITERAL_WHITESPACE, " "))
      end

      def expand_entities(raw)
        return raw unless raw.include?("&")

        parts = []
        index = 0
        while (amp = raw.index("&", index))
          parts << raw[index...amp]
          semi = raw.index(";", amp)
          raise error("unterminated entity reference") unless semi

          reference = raw[(amp + 1)...semi]
          raise error("empty entity reference") if reference.empty?

          parts << resolve_entity(reference)
          index = semi + 1
        end
        parts << raw[index..]
        parts.join
      end

      def resolve_entity(reference)
        if reference.start_with?("#x")
          codepoint(reference[2..], 16)
        elsif reference.start_with?("#")
          codepoint(reference[1..], 10)
        elsif BUILTIN_ENTITIES.key?(reference)
          BUILTIN_ENTITIES[reference]
        else
          # DTD-declared general entities are preserved lexically in
          # the facade's default lane (every adapter answers the
          # reference text). An undeclared reference is malformed.
          raise error("undefined entity &#{reference};") unless @entities.key?(reference)

          "&#{reference};"
        end
      end

      def codepoint(digits, base)
        unless digits.match?(base == 16 ? /\A[0-9A-Fa-f]+\z/ : /\A[0-9]+\z/)
          raise error("malformed character reference")
        end

        code = digits.to_i(base)
        unless valid_xml_char?(code)
          raise error("character reference out of XML range: #{code}")
        end

        [code].pack("U")
      end

      def valid_xml_char?(code)
        code == 0x9 || code == 0xA || code == 0xD ||
          code.between?(0x20, 0xD7FF) ||
          code.between?(0xE000, 0xFFFD) ||
          code.between?(0x10000, 0x10FFFF)
      end

      def scan_name
        match = NAME.match(@source, @pos)
        return unless match && match.begin(0) == @pos

        @pos = match.end(0)
        match[0]
      end

      def skip_whitespace
        @pos += 1 while !at_end? && XML_WHITESPACE.match?(@source[@pos])
      end

      def expect(token)
        return @pos += token.length if start_with?(token)

        raise error("expected #{token.inspect}")
      end

      def start_with?(token)
        @source[@pos, token.length] == token
      end

      def at_end?
        @pos >= @length
      end

      def error(message)
        prefix = @source[0...@pos] || ""
        line = prefix.count("\n") + 1
        column = @pos - (prefix.rindex("\n") || -1)
        ParseError.new(message, line: line, column: column)
      end
    end
  end
end
