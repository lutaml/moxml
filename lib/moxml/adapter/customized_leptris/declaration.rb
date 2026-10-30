# frozen_string_literal: true

# Wrapper for an XML declaration.
#
# Lifecycle record: libleptris models the declaration as document-state
# flags — setters shipped (leptris#1094) and clear shipped
# (leptris#1229, binding 1.9.204.0) — but there is still no first-class
# declaration NODE, so the facade keeps this mutable, removable value
# object as the node stand-in. Dissolves when libleptris exposes
# declaration node identity (leptris#1904's successor surface).

module Moxml
  module Adapter
    module CustomizedLeptris
      # Wrapper for an XML declaration. libleptris gained declaration
      # setters (#1094) but has no first-class declaration node and no
      # way to clear the state, so Moxml exposes this mutable,
      # removable value object instead.
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
