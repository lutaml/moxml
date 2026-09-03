# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      # Wire-format knowledge: the C serializer entry, the
      # canonicalization pass (apostrophes stay literal, optional
      # empty-element expansion), and the literal-region scanner that
      # keeps both from touching CDATA/comment/PI content.
      module Serialize
        # moxml canonical serialization: apostrophes stay literal
        # (only & < > " are escaped) and empty elements expand when the
        # caller asked for it — matching the other adapters' contract.
        # Runs segment-aware: CDATA content is literal and must not be
        # touched.
        # Regions whose content is literal and must never be rewritten.
        # Scanned positionally (String#index), not with a regex: the
        # scan is linear in the input length, so pathological document
        # content cannot blow up the serializer.
        LITERAL_REGIONS = {
          "<!--" => "-->",
          "<![CDATA[" => "]]>",
          "<?" => "?>",
        }.freeze

        # All quantifiers are possessive and the bare-part class
        # excludes "/" and ">": the possessive groups can never consume
        # the closing delimiter, so no backtracking is possible and the
        # match is linear even on malformed tags.
        EMPTY_ELEMENT_RE = %r{<([A-Za-z_][\w.:-]*+)((?:"[^"]*+"|'[^']*+'|[^<>"'/]++)*+)/>}

        def serialize(node, options = {})
          # Entity restoration belongs to the wrapper layer
          # (Node#to_xml runs adapter.restore_entities for every
          # adapter); doing it here scanned the output a second time.
          xml = normalize_serialization(raw_serialize(node, options), options)
          # The binding's FFI strings come back binary-tagged; the
          # engine encoded the bytes per this option, so tag them.
          xml.force_encoding(options[:encoding]) if options[:encoding]
          xml
        end

        def raw_serialize(node, options)
          # CDATA must precede Text in this chain: CDATA < Text in the
          # binding, so a Text branch first would swallow CDATA nodes.
          case node
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference, CustomizedLeptris::DocumentPI
            return node.to_xml
          when ::Leptris::XML::CDATA
            return XmlEmitter.cdata(node.content)
          when ::Leptris::XML::Comment
            return "<!--#{node.content}-->"
          when ::Leptris::XML::ProcessingInstruction
            content = node.content.to_s
            return content.empty? ? "<?#{node.target}?>" : "<?#{node.target} #{content}?>"
          when ::Leptris::XML::Text, CustomizedLeptris::TextSegment
            return XmlEmitter.escape_text(node.content.to_s)
          when ::Leptris::XML::Document
            return serialize_document(node, options)
          end

          include_decl = options.fetch(:declaration) do
            options[:no_declaration] ? false : document_has_declaration?(node)
          end
          kwargs = {
            indent: options.fetch(:indent, 0),
            no_decl: !include_decl,
            encoding: options[:encoding],
          }
          if INDENT_UNIT_SUPPORTED && options[:indent_text].is_a?(String)
            kwargs[:indent_text] = options[:indent_text]
          end
          xml = node.to_xml(**kwargs)
          # Element output always ends with the close tag — but the
          # engine's serializer appends a stray trailing newline when
          # the element's last text child is non-ASCII (fixed engine
          # side in 1.9.42; kept for older floor bindings).
          xml.sub(/\n+\z/, "")
        end

        # A bare ampersand — not starting a named or numeric entity
        # reference. Some engine builds (observed: the Linux 1.9.50
        # platform gem) emit text-content ampersands unescaped; the
        # detection below is a no-op on correct builds.
        RAW_AMP_RE = /&(?!#{Entity::NAME_PATTERN};|#\d+;|#x[0-9A-Fa-f]+;)/

        def normalize_serialization(xml, options)
          # The libxml2-layout serializer (>= 1.9.42) keeps attribute
          # apostrophes literal; older engines escaped them.
          needs_apos = !LIBXML2_LAYOUT_PARITY && xml.include?("&apos;")
          needs_expand = options[:expand_empty] && xml.include?("/>")
          # One scan: the bare-ampersand regex fails fast on
          # ampersand-free output — no include? pre-filter needed.
          needs_amp = xml.match?(RAW_AMP_RE)
          return xml unless needs_apos || needs_expand || needs_amp

          out = +""
          pos = 0
          while pos < xml.length
            opener_at, terminator = next_literal_region(xml, pos)
            if opener_at.nil?
              out << normalize_markup(xml[pos..], needs_apos, needs_expand, needs_amp: needs_amp)
              break
            end

            out << normalize_markup(xml[pos...opener_at], needs_apos, needs_expand, needs_amp: needs_amp)
            search_from = opener_at + opener_at_offset(terminator)
            close = xml.index(terminator, search_from)
            close_end = close.nil? ? xml.length : close + terminator.length
            out << xml[opener_at...close_end]
            pos = close_end
          end
          out
        end

        # Nearest literal region at/after from: [position, terminator].
        def next_literal_region(xml, from)
          best = nil
          best_terminator = nil
          LITERAL_REGIONS.each do |opener, terminator|
            idx = xml.index(opener, from)
            next if idx.nil?

            if best.nil? || idx < best
              best = idx
              best_terminator = terminator
            end
          end
          best.nil? ? nil : [best, best_terminator]
        end

        # Search for a terminator past its opener's overlap-safe offset
        # ("-->" cannot start inside "<!--").
        def opener_at_offset(terminator)
          terminator == "-->" ? 4 : 0
        end

        def normalize_markup(markup, needs_apos, needs_expand, needs_amp: false)
          markup = markup.gsub("&apos;", "'") if needs_apos
          if needs_expand
            markup = markup.gsub(EMPTY_ELEMENT_RE) do
              "<#{Regexp.last_match(1)}#{Regexp.last_match(2)}></#{Regexp.last_match(1)}>"
            end
          end
          # Segment-aware: this never sees CDATA/comment/PI content,
          # where a bare & is literal data.
          markup = markup.gsub(RAW_AMP_RE, "&amp;") if needs_amp
          markup
        end
      end
    end
  end
end
