# frozen_string_literal: true

module Moxml
  module Adapter
    class Base
      # include XmlUtils

      # Entity round-trip pipeline lives in Moxml::Entity; these
      # constants and methods stay on the adapter protocol so
      # adapters and wrappers keep their calling convention.
      ENTITY_MARKER = Entity::MARKER
      ENTITY_NAME_PATTERN = Entity::NAME_PATTERN
      ENTITY_NAME_RE = Entity::NAME_RE
      ENTITY_MARKER_RE = Entity::MARKER_RE
      SERIALIZED_ENTITY_MARKER_RE = Entity::SERIALIZED_MARKER_RE
      STANDARD_ENTITIES = Entity::STANDARD_ENTITIES

      class << self
        include XmlUtils

        def preprocess_entities(xml)
          Entity.preprocess_entities(xml)
        end

        def decode_entities(text)
          Entity.decode_entities(text)
        end

        def restore_entities(text)
          Entity.restore_entities(text)
        end

        def set_root(_doc, _element)
          raise Moxml::NotImplementedError.new(
            "set_root not implemented",
            feature: "set_root",
            adapter: name,
          )
        end

        def parse(_xml, _options = {}, _context = nil)
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

        # Mutation return contract: protocol methods that may change
        # which native a wrapper tracks (set_attribute_name,
        # set_namespace, set_attribute_value) always return the native
        # the wrapper must keep tracking — the same object when
        # mutated in place, a fresh object when the adapter recreates
        # the node.
        def set_attribute_name(attribute, name)
          attribute.name = name
          attribute
        end

        def set_namespace(_node, _namespace)
          raise Moxml::NotImplementedError.new(
            "set_namespace not implemented",
            feature: "set_namespace",
            adapter: name,
          )
        end

        def set_attribute_value(attribute, value)
          attribute.value = value
          attribute
        end

        # Remove a specific native attribute node from its owning
        # element. Semantics (which attribute a name addresses) live
        # in Moxml::AttributeResolver; this is the raw primitive.
        def remove_attribute_native(attr)
          attr.remove
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

        # Check if the native document has an XML declaration
        # @param native_doc the native document object
        # @param wrapper [Moxml::Document] the wrapper with has_xml_declaration flag
        # @return [Boolean]
        def has_declaration?(_native_doc, wrapper)
          wrapper.has_xml_declaration
        end

        # Clear the declaration state from the native document.
        # Called when a Declaration node is removed from a document.
        def remove_declaration(_native_doc); end

        # Source line of a native node (1-based), or nil when the
        # underlying backend does not track source positions.
        # Adapters that track lines (Nokogiri, LibXML) override this.
        def line_number(_node)
          nil
        end

        # Local name of a native attribute node. Adapters whose natives
        # carry qualified names override this to expose the local part;
        # the wrapper composes the prefix.
        def attribute_name(attr)
          attr.name
        end

        # Return the actual native node after an add_child operation.
        # Override for adapters where node identity may change (e.g., LibXML doc.root=).
        def actual_native(child_native, _parent_native)
          child_native
        end

        # Whether `Node.wrap` may safely memoize the wrapper for this
        # native across calls. Adapters whose parser hands back the
        # same Ruby object for the same logical node (nokogiri, ox,
        # oga, rexml, leptris) opt in (default true). Adapters that
        # mint a new Ruby object per access (libxml) opt out so the
        # identity map does not accumulate dead entries.
        def wrappers_recyclable?
          true
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
