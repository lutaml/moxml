# frozen_string_literal: true

module Moxml
  class Text < Node
    def content
      text = raw_content
      adapter.restore_entities(text)
    end

    # Returns raw content without entity marker restoration.
    def raw_content
      adapter.text_content(@native)
    end

    def content=(text)
      adapter.set_text_content(@native, normalize_xml_value(text))
    end

    # A Text node's natural string representation is its text value. Without
    # this override, `"#{text_node}"` and `p text_node` would inherit
    # Object#inspect's `"#<Moxml::Text:0xaddr>"` form and silently corrupt any
    # output stream the node is interpolated into.
    def to_s
      content
    end

    alias_method :inspect, :to_s
  end
end
