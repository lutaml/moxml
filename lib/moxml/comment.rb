# frozen_string_literal: true

module Moxml
  module Comment
    include Node

    def content
      adapter.comment_content(@native)
    end

    def content=(text)
      text = normalize_xml_value(text)
      adapter.validate_comment_content(text)
      adapter.set_comment_content(@native, text)
    end

    # See Moxml::Text#text — Node#text's base is "" for non-elements.
    alias_method :text, :content
  end
end
