# frozen_string_literal: true

require_relative "../xml_utils"
require_relative "../document_builder"

module Moxml
  module Adapter
    class Base
      # include XmlUtils

      # Entity marker for adapters that resolve entities during parsing.
      # U+FFFC (Object Replacement Character) + U+FEFF (BOM) is a two-character
      # sentinel chosen because this exact sequence followed by a valid entity
      # name pattern is vanishingly unlikely in real XML content.
      # Non-standard entities like &copy; are converted to this marker before
      # parsing, then restored during serialization.
      # Standard XML entities (&amp; &lt; &gt; &quot; &apos;) are NOT converted.
      ENTITY_MARKER = "\u{FFFC}\u{FEFF}"
      ENTITY_NAME_PATTERN = "[a-zA-Z_][\\w.:-]*"
      ENTITY_NAME_RE = /&(#{ENTITY_NAME_PATTERN});/
      ENTITY_MARKER_RE = /\u{FFFC}\u{FEFF}(#{ENTITY_NAME_PATTERN});/
      SERIALIZED_ENTITY_MARKER_RE = /&#xFFFC;&#xFEFF;(#{ENTITY_NAME_PATTERN});/
      STANDARD_ENTITIES = %w[amp lt gt quot apos].freeze

      class << self
        include XmlUtils

        # Replace non-standard entity references with markers before parsing.
        # Always returns a UTF-8 encoded string.
        def preprocess_entities(xml)
          return "" if xml.nil?

          str = if xml.encoding == Encoding::BINARY
                  # Binary strings are assumed to be UTF-8. If the bytes are
                  # not valid UTF-8, fall back to encoding as UTF-8 with
                  # replacement to avoid raising on gsub.
                  dup = xml.dup.force_encoding("UTF-8")
                  dup.valid_encoding? ? dup : xml.dup.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace)
                elsif xml.encoding == Encoding::UTF_8
                  xml
                else
                  xml.encode("UTF-8")
                end
          str.gsub(ENTITY_NAME_RE) do |match|
            STANDARD_ENTITIES.include?(::Regexp.last_match(1)) ? match : "#{ENTITY_MARKER}#{::Regexp.last_match(1)};"
          end
        end

        # Restore entity markers back to named entity references.
        def restore_entities(text)
          return text unless text.is_a?(String)

          # Force UTF-8 encoding since markers are UTF-8 characters
          str = text.encoding == Encoding::UTF_8 ? text : text.dup.force_encoding("UTF-8")
          result = str.gsub(ENTITY_MARKER_RE, '&\1;')
          result.gsub(SERIALIZED_ENTITY_MARKER_RE, '&\1;')
        end

        def set_root(_doc, _element)
          raise Moxml::NotImplementedError.new(
            "set_root not implemented",
            feature: "set_root",
            adapter: name,
          )
        end

        def parse(_xml, _options = {})
          raise Moxml::NotImplementedError.new(
            "parse not implemented",
            feature: "parse",
            adapter: name,
          )
        end

        # Parse XML using SAX (event-driven) parsing
        #
        # SAX parsing provides a memory-efficient way to process XML
        # by triggering events as the document is parsed, rather than
        # building a complete DOM tree.
        #
        # @param xml [String, IO] XML string or IO object to parse
        # @param handler [Moxml::SAX::Handler] Handler object receiving events
        # @return [void]
        # @raise [Moxml::NotImplementedError] if adapter doesn't support SAX
        def sax_parse(_xml, _handler)
          raise Moxml::NotImplementedError.new(
            "sax_parse not implemented",
            feature: "sax_parse",
            adapter: name,
          )
        end

        # Check if this adapter supports SAX parsing
        #
        # @return [Boolean] true if SAX parsing is supported
        def sax_supported?
          respond_to?(:sax_parse) &&
            method(:sax_parse).owner != Moxml::Adapter::Base.singleton_class
        end

        def create_document(_native_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_document not implemented",
            feature: "create_document",
            adapter: name,
          )
        end

        def create_element(name, owner_doc: nil)
          validate_element_name(name)
          create_native_element(name, owner_doc)
        end

        def create_text(content, owner_doc: nil)
          # Ox freezes the content, so we need to dup it
          create_native_text(normalize_xml_value(content).dup, owner_doc)
        end

        def create_cdata(content, owner_doc: nil)
          create_native_cdata(normalize_xml_value(content), owner_doc)
        end

        def create_comment(content, owner_doc: nil)
          validate_comment_content(content)
          create_native_comment(normalize_xml_value(content), owner_doc)
        end

        def create_doctype(name, external_id, system_id)
          create_native_doctype(name, external_id, system_id)
        end

        def create_processing_instruction(target, content)
          validate_pi_target(target)
          create_native_processing_instruction(target,
                                               normalize_xml_value(content))
        end

        def create_declaration(version = "1.0", encoding = "UTF-8",
                               standalone = nil)
          validate_declaration_version(version)
          validate_declaration_encoding(encoding)
          validate_declaration_standalone(standalone)
          create_native_declaration(version, encoding, standalone)
        end

        def create_namespace(element, prefix, uri,
namespace_validation_mode: :strict)
          if prefix && uri.to_s.empty?
            raise NamespaceError.new(
              "Prefixed namespace declaration cannot have an empty URI",
              prefix: prefix,
              uri: uri,
            )
          end
          if namespace_validation_mode == :strict
            validate_prefix(prefix) if prefix
            validate_uri(uri, mode: :strict)
          else
            validate_uri(uri, mode: :lenient)
          end
          create_native_namespace(element, prefix, uri)
        end

        def create_entity_reference(name)
          validate_entity_reference_name(name)
          create_native_entity_reference(name)
        end

        def set_attribute_name(attribute, name)
          attribute.name = name
        end

        def set_attribute_value(attribute, value)
          attribute.value = value
        end

        def entity_reference_name(node)
          node.name
        end

        def duplicate_node(node)
          node.dup
        end

        def patch_node(node, _parent = nil)
          # monkey-patch the native node if necessary
          node
        end

        def prepare_for_new_document(node, _target_doc)
          # Hook for adapters that need special handling when moving nodes
          # between documents (e.g., LibXML's document.import)
          # Default: no-op for backward compatibility
          node
        end

        # Check if the native document has an XML declaration
        # @param native_doc the native document object
        # @param wrapper [Moxml::Document] the wrapper with has_xml_declaration flag
        # @return [Boolean]
        def has_declaration?(_native_doc, wrapper)
          wrapper.has_xml_declaration
        end

        # Return the actual native node after an add_child operation.
        # Override for adapters where node identity may change (e.g., LibXML doc.root=).
        def actual_native(child_native, _parent_native)
          child_native
        end

        # Returns all namespaces in scope for this element, including
        # inherited from ancestors. Adapters with native support (Nokogiri)
        # override this. Default walks the ancestor chain.
        def in_scope_namespaces(element)
          namespaces = {}
          node = element

          while node
            break unless node_type(node) == :element

            namespace_definitions(node).each do |ns|
              prefix = namespace_prefix(ns)
              namespaces[prefix] = ns unless namespaces.key?(prefix)
            end
            node = parent(node)
          end

          namespaces.values
        end

        protected

        def create_native_element(_name, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_element not implemented",
            feature: "create_native_element",
            adapter: name,
          )
        end

        def create_native_text(_content, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_text not implemented",
            feature: "create_native_text",
            adapter: name,
          )
        end

        def create_native_cdata(_content, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_cdata not implemented",
            feature: "create_native_cdata",
            adapter: name,
          )
        end

        def create_native_comment(_content, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_comment not implemented",
            feature: "create_native_comment",
            adapter: name,
          )
        end

        def create_native_doctype(_name, _external_id, _system_id)
          raise Moxml::NotImplementedError.new(
            "create_native_doctype not implemented",
            feature: "create_native_doctype",
            adapter: name,
          )
        end

        def create_native_processing_instruction(_target, _content)
          raise Moxml::NotImplementedError.new(
            "create_native_processing_instruction not implemented",
            feature: "create_native_processing_instruction",
            adapter: name,
          )
        end

        def create_native_declaration(_version, _encoding, _standalone)
          raise Moxml::NotImplementedError.new(
            "create_native_declaration not implemented",
            feature: "create_native_declaration",
            adapter: name,
          )
        end

        def create_native_namespace(_element, _prefix, _uri)
          raise Moxml::NotImplementedError.new(
            "create_native_namespace not implemented",
            feature: "create_native_namespace",
            adapter: name,
          )
        end

        def create_native_entity_reference(_name)
          raise Moxml::NotImplementedError.new(
            "create_native_entity_reference not implemented",
            feature: "create_native_entity_reference",
            adapter: name,
          )
        end
      end
    end
  end
end
