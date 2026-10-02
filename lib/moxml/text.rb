# frozen_string_literal: true

module Moxml
  module Text
    include Node

    def content
      # Engines allocate a fresh String per read (Nokogiri
      # node.text); hydration walks re-read the same text wrappers —
      # this read was the single largest string allocation site in
      # large-document metanorma compiles. Cleared by content=.
      @content ||= begin
        text = raw_content
        entity_bearing? ? adapter.restore_entities(text) : text
      end
    end

    # Returns raw content without entity marker restoration.
    def raw_content
      adapter.text_content(@native)
    end

    def content=(text)
      @content = nil
      adapter.set_text_content(@native, normalize_xml_value(text))
    end

    def to_s
      content
    end

    # Node#text's base returns "" for non-element nodes; a text
    # node's text IS its content (leptris's Reads layer already
    # answered content here — the wrapper contract now matches on
    # every adapter). Aliased, not delegated: text rides the
    # walk-hot read path (moxml#336) and pays one frame, not two.
    alias_method :text, :content

    # Nokogiri-compatible DOM name: text nodes are named "text".
    def name
      "text"
    end

    # Nokogiri-compatible: renaming non-element nodes is a no-op
    def name=(_value); end
  end
end
