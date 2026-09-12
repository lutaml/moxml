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
          xml = if native_expand?(node, options)
                  opts = options.dup
                  opts[:__expand_handled_natively] = true
                  normalize_serialization(raw_serialize(node, opts), opts)
                else
                  normalize_serialization(raw_serialize(node, options), options)
                end
          # The binding's FFI strings come back binary-tagged; the
          # engine encoded the bytes per this option, so tag them.
          xml.force_encoding(options[:encoding]) if options[:encoding]
          xml
        end

        # Element-face trailing-newline strip: engine fix landed in
        # 1.9.42; armed only on older floor bindings.
        TRAILING_NL_STRIP_ACTIVE =
          Gem::Version.new(::Leptris::VERSION) < Gem::Version.new("1.9.42")

        # The binding's element face with all-default options — the
        # frozen splat keeps the hot argless path allocation-free.
        # Native expand-empty (engine #882, libleptris 1.9.95,
        # bindings 1.9.144): empty elements emit <a></a> through a
        # C-side ext entry — the Ruby full-output regex rewrite and
        # its "/>" probe scan drop out of the element path. The
        # document face does not expose the option yet; documents
        # keep the Ruby pass.
        EXPAND_EMPTY_NATIVE =
          Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.144")

        ELEMENT_DEFAULT_KWARGS = { indent: 0, no_decl: true, encoding: nil }.freeze
        ELEMENT_EXPAND_KWARGS =
          if EXPAND_EMPTY_NATIVE
            { indent: 0, no_decl: true, encoding: nil, expand_empty: true }.freeze
          else
            ELEMENT_DEFAULT_KWARGS
          end.freeze

        # Elements (not documents) with expand_empty and NO
        # indent-unit string: the C ext entry handles expansion. The
        # element unit serializer does not take the flag — those keep
        # the Ruby pass.
        def native_expand?(node, options)
          EXPAND_EMPTY_NATIVE && options[:expand_empty] &&
            !node.is_a?(::Leptris::XML::Document) &&
            !options[:indent_text].is_a?(String)
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

          # Element serialization never emits a declaration — the C
          # element serializer ignores the flag (verified
          # byte-identical); skipping the declaration fetch avoids a
          # document attachment walk per element serialize. Likewise
          # an unset encoding serializes UTF-8 — byte-identical to an
          # explicit "UTF-8" — and the binding then reuses its shared
          # DEFAULT_OPTIONS instead of rebuilding an options struct
          # per call; the wrapper force-tags the string either way.
          indent = options.fetch(:indent, 0)
          encoding = options[:encoding] == "UTF-8" ? nil : options[:encoding]
          native_expand = native_expand?(node, options)
          xml = if indent.zero? && encoding.nil?
                  node.to_xml(**(native_expand ? ELEMENT_EXPAND_KWARGS : ELEMENT_DEFAULT_KWARGS))
                else
                  kwargs = { indent: indent, no_decl: true, encoding: encoding }
                  kwargs[:expand_empty] = true if native_expand
                  if INDENT_UNIT_SUPPORTED && options[:indent_text].is_a?(String)
                    kwargs[:indent_text] = options[:indent_text]
                  end
                  node.to_xml(**kwargs)
                end
          # Element output always ends with the close tag — but older
          # engines append a stray trailing newline when the element's
          # last text child is non-ASCII (fixed engine side in
          # 1.9.42). The strip stays armed only below that version —
          # a regex sub per element serialize is measurable in bulk.
          TRAILING_NL_STRIP_ACTIVE ? xml.sub(/\n+\z/, "") : xml
        end

        # A bare ampersand — not starting a named or numeric entity
        # reference. Some engine builds (observed: the Linux 1.9.50
        # platform gem) emit text-content ampersands unescaped; the
        # detection below is a no-op on correct builds.
        RAW_AMP_RE = /&(?!#{Entity::NAME_PATTERN};|#\d+;|#x[0-9A-Fa-f]+;)/

        # A raw "<" in text position — the engine intermittently
        # lost the escape when parsing under allocation pressure
        # (leptris-ruby#131), so a decoded &#x3c; serialized bare and
        # reparsing truncated at it. Fixed in leptris 1.9.80 (verified
        # 0/200 on the churn repro); the guard stays armed below that
        # version and for any future build that regresses — the
        # parse-under-pressure spec in leptris_spec fails loudly if a
        # fixed-version build corrupts while the guard is stood down.
        RAW_LT_RE = /<(?![A-Za-z_:\/?!])/
        RAW_LT_TRIGGER_RE = /<[^A-Za-z_:\/?!]/
        RAW_LT_GUARD_ACTIVE =
          Gem::Version.new(::Leptris::VERSION) < Gem::Version.new("1.9.80")

        def normalize_serialization(xml, options)
          # The libxml2-layout serializer (>= 1.9.42) keeps attribute
          # apostrophes literal; older engines escaped them.
          needs_apos = !LIBXML2_LAYOUT_PARITY && xml.include?("&apos;")
          needs_expand = options[:expand_empty] &&
                         !options[:__expand_handled_natively] &&
                         xml.include?("/>")
          # Corruption guards: the 1-char ampersand probe is ~1µs
          # (memchr-class); the raw-< scan runs only on builds that
          # still carry the parse race (leptris-ruby#131).
          needs_amp = xml.include?("&") && xml.match?(RAW_AMP_RE)
          needs_lt = RAW_LT_GUARD_ACTIVE && xml.match?(RAW_LT_TRIGGER_RE)
          return xml unless needs_apos || needs_expand || needs_amp || needs_lt

          out = +""
          pos = 0
          while pos < xml.length
            opener_at, terminator = next_literal_region(xml, pos)
            if opener_at.nil?
              out << normalize_markup(xml[pos..], needs_apos, needs_expand,
                                      needs_amp: needs_amp, needs_lt: needs_lt)
              break
            end

            out << normalize_markup(xml[pos...opener_at], needs_apos, needs_expand,
                                    needs_amp: needs_amp, needs_lt: needs_lt)
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

        def normalize_markup(markup, needs_apos, needs_expand, needs_amp: false, needs_lt: false)
          markup = markup.gsub("&apos;", "'") if needs_apos
          if needs_expand
            markup = markup.gsub(EMPTY_ELEMENT_RE) do
              "<#{Regexp.last_match(1)}#{Regexp.last_match(2)}></#{Regexp.last_match(1)}>"
            end
          end
          # Segment-aware: this never sees CDATA/comment/PI content,
          # where bare & and < are literal data.
          markup = markup.gsub(RAW_AMP_RE, "&amp;") if needs_amp
          markup = markup.gsub(RAW_LT_RE, "&lt;") if needs_lt
          markup
        end
      end
    end
  end
end
