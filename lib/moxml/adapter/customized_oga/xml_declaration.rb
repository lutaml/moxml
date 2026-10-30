# frozen_string_literal: true

# Stand-in XML declaration node.
#
# Engine gap (upstream oga): Oga::XML::XmlDeclaration is not writable —
# version/encoding/standalone cannot be set on an instance the way the
# facade contract requires, so this subclass owns the state and renders
# the declaration itself. Upstream tracker:
# https://github.com/yorickpeterse/oga

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
