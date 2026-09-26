# frozen_string_literal: true

module Moxml
  module Text
    include Node

    def content
      text = raw_content
      entity_bearing? ? adapter.restore_entities(text) : text
    end

    # Returns raw content without entity marker restoration.
    def raw_content
      adapter.text_content(@native)
    end

    def content=(text)
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
  end
end
