# frozen_string_literal: true

module Moxml
  class Declaration < Node
    ALLOWED_VERSIONS = ["1.0", "1.1"].freeze
    ALLOWED_STANDALONE = %w[yes no].freeze
    ALLOWED_ATTRIBUTES = %w[version encoding standalone].freeze

    def version
      adapter.declaration_attribute(@native, "version")
    end

    def version=(new_version)
      adapter.validate_declaration_version(new_version)
      adapter.set_declaration_attribute(@native, "version", new_version)
    end

    def encoding
      adapter.declaration_attribute(@native, "encoding")
    end

    def encoding=(new_encoding)
      adapter.validate_declaration_encoding(new_encoding)
      adapter.set_declaration_attribute(@native, "encoding", new_encoding)
    end

    def standalone
      adapter.declaration_attribute(@native, "standalone")
    end

    def standalone=(new_standalone)
      adapter.validate_declaration_standalone(new_standalone)
      adapter.set_declaration_attribute(@native, "standalone", new_standalone)
    end

    def remove
      # Mark document as having no declaration when declaration is removed
      # Store on native document so all wrappers see it
      native_doc = adapter.document(@native)
      native_doc&.instance_variable_set(:@moxml_has_declaration, false)

      super
    end

    def declaration?
      true
    end
  end
end
