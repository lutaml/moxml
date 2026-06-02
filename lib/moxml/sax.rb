# frozen_string_literal: true

module Moxml
  module SAX
    autoload :Handler, "moxml/sax/handler"
    autoload :ElementHandler, "moxml/sax/element_handler"
    autoload :BlockHandler, "moxml/sax/block_handler"
    autoload :NamespaceSplitter, "moxml/sax/namespace_splitter"
  end
end
