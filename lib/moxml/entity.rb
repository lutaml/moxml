# frozen_string_literal: true

module Moxml
  # Entity-reference round-trip pipeline.
  #
  # XML libraries split into two camps: those that preserve named
  # entity references natively (nokogiri) and those that expand or
  # reject them at parse (ox, rexml, oga, libxml, leptris). Moxml
  # bridges the camps with one pipeline, owned here and delegated to
  # by Adapter::Base:
  #
  # 1. Parse time — .preprocess_entities rewrites non-standard
  #    entity references to a two-character marker (see MARKER) so
  #    the reference survives native parsing verbatim. The five
  #    standard entities (&amp; &lt; &gt; &quot; &apos;) are NOT
  #    converted.
  # 2. Read time — marker-bearing text is split into text and
  #    Entity::Reference nodes (adapters whose natives cannot hold
  #    references), or decoded in place (.decode_entities covers the
  #    five standard entities plus numeric character references).
  # 3. Serialize time — .restore_entities maps markers back to named
  #    references, including markers a native serializer already
  #    rendered as character references.
  #
  # How references are STORED between parse and serialize is
  # adapter-shaped (in-tree value objects for ox, attachment
  # sequences for rexml/libxml, text markers for oga/leptris); the
  # marker lifecycle and the Entity::Reference value type are the
  # shared, single-sourced parts.
  module Entity
    autoload :Reference, "moxml/entity/reference"
    autoload :Restorer, "moxml/entity/restorer"

    # Marker for adapters that resolve entities during parsing.
    # U+FFFC (Object Replacement Character) + U+FEFF (BOM) is a
    # two-character sentinel chosen because this exact sequence
    # followed by a valid entity name pattern is vanishingly unlikely
    # in real XML content.
    MARKER = "\u{FFFC}\u{FEFF}"
    NAME_PATTERN = "[a-zA-Z_][\\w.:-]*"
    NAME_RE = /&(#{NAME_PATTERN});/
    MARKER_RE = /\u{FFFC}\u{FEFF}(#{NAME_PATTERN});/
    SERIALIZED_MARKER_RE = /&#xFFFC;&#xFEFF;(#{NAME_PATTERN});/
    STANDARD_ENTITIES = %w[amp lt gt quot apos].freeze

    # One regex pass, no allocations: true when a NON-standard named
    # entity exists somewhere. Documents carrying only the five
    # predefined entities (the overwhelmingly common case) skip the
    # marker gsub's full-buffer copy entirely.
    NON_STANDARD_ENTITY_RE = /&(?!amp;|lt;|gt;|quot;|apos;)(#{NAME_PATTERN});/

    NAMED_DECODE_MAP = {
      "amp" => "&", "lt" => "<", "gt" => ">",
      "quot" => '"', "apos" => "'"
    }.freeze
    private_constant :NAMED_DECODE_MAP

    DECODE_RE = /&(?:(amp|lt|gt|quot|apos)|#(?:(\d+)|[xX]([0-9a-fA-F]+)));/
    private_constant :DECODE_RE

    module_function

    # Replace non-standard entity references with markers before
    # parsing. Always returns a UTF-8 encoded string, and reports
    # whether the result can contain markers: the flag rides the
    # same `&` scan, so callers needing it (leptris parse) avoid a
    # second full-buffer multibyte probe.
    def preprocess_with_marker_flag(xml)
      return ["", false] if xml.nil?

      str = if xml.encoding == Encoding::BINARY
              # Binary strings are assumed to be UTF-8. If the bytes are
              # not valid UTF-8, fall back to encoding as UTF-8 with
              # replacement to avoid raising on gsub.
              dup = xml.dup.force_encoding("UTF-8")
              if dup.valid_encoding?
                dup
              else
                xml.dup.encode("UTF-8",
                               "ASCII-8BIT", invalid: :replace, undef: :replace)
              end
            elsif xml.encoding == Encoding::UTF_8
              xml
            else
              xml.encode("UTF-8")
            end
      # Fast path: no `&` means no entity references to mark — skip
      # the regex scan and string allocation entirely. The vast
      # majority of XML payloads contain no entity references.
      return [str, false] unless str.include?("&")
      # Second fast path: only predefined entities — the gsub would
      # pass every match through unchanged, so skip its full-buffer
      # copy too.
      return [str, false] unless str.match?(NON_STANDARD_ENTITY_RE)

      marked = false
      processed = str.gsub(NAME_RE) do |match|
        name = ::Regexp.last_match(1)
        if STANDARD_ENTITIES.include?(name)
          match
        else
          marked = true
          "#{MARKER}#{name};"
        end
      end
      [processed, marked]
    end

    def preprocess_entities(xml)
      preprocess_with_marker_flag(xml)[0]
    end

    # Resolve numeric (&#NN; / &#xNN;) and the five standard named
    # (&amp; &lt; &gt; &quot; &apos;) XML entity references in one
    # single pass. The resulting characters are data; no further
    # decoding is applied. Numeric refs producing invalid UTF-8
    # (NUL, surrogate halves, > U+10FFFF) are preserved verbatim
    # to avoid silently emitting malformed bytes.
    def decode_entities(text)
      return text unless text.is_a?(String) && text.include?("&")

      text.gsub(DECODE_RE) do
        if (named = ::Regexp.last_match(1))
          NAMED_DECODE_MAP[named]
        else
          code = ::Regexp.last_match(2) ? ::Regexp.last_match(2).to_i : ::Regexp.last_match(3).to_i(16)
          if code.zero? || code.between?(0xD800, 0xDFFF) || code > 0x10FFFF
            ::Regexp.last_match(0)
          else
            [code].pack("U")
          end
        end
      end
    end

    # Restore entity markers back to named entity references.
    def restore_entities(text)
      return text unless text.is_a?(String)

      # Force UTF-8 encoding since markers are UTF-8 characters
      str = text.encoding == Encoding::UTF_8 ? text : text.dup.force_encoding("UTF-8")
      # Fast path: the vast majority of documents carry no entity
      # markers — two C-level scans beat two regex passes.
      return str unless str.include?(MARKER) ||
        str.include?("&#xFFFC;")

      result = str.gsub(MARKER_RE, '&\1;')
      result.gsub(SERIALIZED_MARKER_RE, '&\1;')
    end
  end
end
