# frozen_string_literal: true

require "oga"

module Moxml
  module Adapter
    module CustomizedOga
      class XmlDeclaration < ::Oga::XML::XmlDeclaration
        def initialize(options = {})
          @version    = options[:version] || "1.0"
          @encoding   = options[:encoding]
          @standalone = options[:standalone]
        end

        def to_xml
          parts = ["<?xml"]
          parts << %( version="#{version}") if version
          parts << %( encoding="#{encoding}") if encoding
          parts << %( standalone="#{standalone}") if standalone
          "#{parts.join}?>"
        end
      end
    end
  end
end
