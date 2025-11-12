# frozen_string_literal: true

require_relative "../xml_utils"
require_relative "../document_builder"

module Moxml
  module Adapter
    class Base
      # include XmlUtils

      class << self
        include XmlUtils

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

        def create_document(_native_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_document not implemented",
            feature: "create_document",
            adapter: name,
          )
        end

        def create_element(name)
          validate_element_name(name)
          create_native_element(name)
        end

        def create_text(content)
          # Ox freezes the content, so we need to dup it
          create_native_text(normalize_xml_value(content).dup)
        end

        def create_cdata(content)
          create_native_cdata(normalize_xml_value(content))
        end

        def create_comment(content)
          validate_comment_content(content)
          create_native_comment(normalize_xml_value(content))
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

        def create_namespace(element, prefix, uri)
          validate_prefix(prefix) if prefix
          validate_uri(uri)
          create_native_namespace(element, prefix, uri)
        end

        def set_attribute_name(attribute, name)
          attribute.name = name
        end

        def set_attribute_value(attribute, value)
          attribute.value = value
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

        protected

        def create_native_element(_name)
          raise Moxml::NotImplementedError.new(
            "create_native_element not implemented",
            feature: "create_native_element",
            adapter: name,
          )
        end

        def create_native_text(_content)
          raise Moxml::NotImplementedError.new(
            "create_native_text not implemented",
            feature: "create_native_text",
            adapter: name,
          )
        end

        def create_native_cdata(_content)
          raise Moxml::NotImplementedError.new(
            "create_native_cdata not implemented",
            feature: "create_native_cdata",
            adapter: name,
          )
        end

        def create_native_comment(_content)
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
      end
    end
  end
end
