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
  end
end
