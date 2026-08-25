# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # Wrapper for an XML declaration. libleptris stores declaration
      # data on the document struct (read-only, serialized via options)
      # and has no first-class declaration node, so Moxml exposes this
      # mutable value object instead.
      class Declaration
        attr_accessor :version, :encoding, :standalone, :parent_doc

        def initialize(version = "1.0", encoding = "UTF-8", standalone = nil)
          @version = version
          @encoding = encoding
          @standalone = standalone
        end

        def to_xml
          XmlEmitter.declaration_xml(version, encoding, standalone)
        end

        def ==(other)
          other.is_a?(self.class) &&
            version == other.version &&
            encoding == other.encoding &&
            standalone == other.standalone
        end
      end
    end
  end
end
