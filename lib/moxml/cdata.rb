# frozen_string_literal: true

module Moxml
  module Cdata
    include Node

    def content
      adapter.cdata_content(@native)
    end

    def content=(text)
      adapter.set_cdata_content(@native, normalize_xml_value(text))
    end

    # See Moxml::Text#text — Node#text's base is "" for non-elements.
    alias_method :text, :content
  end
end
