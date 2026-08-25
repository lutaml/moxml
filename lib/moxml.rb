# frozen_string_literal: true

module Moxml
  class << self
    def new(adapter = nil, &block)
      context = Context.new(adapter)
      context.config.instance_eval(&block) if block
      context
    end

    def parse(xml, adapter: nil, **options)
      Context.new(adapter).parse(xml, options)
    end

    def configure
      yield Config.default if block_given?
    end

    def with_config(adapter_name = nil, strict_parsing = nil,
                    default_encoding = nil)
      original = Config.default
      saved_values = {
        adapter: original.adapter_name,
        strict_parsing: original.strict_parsing,
        default_encoding: original.default_encoding,
        default_indent: original.default_indent,
        default_line_ending: original.default_line_ending,
        entity_load_mode: original.entity_load_mode,
        restore_entities: original.restore_entities,
        namespace_validation_mode: original.namespace_validation_mode,
        entity_restoration_mode: original.entity_restoration_mode,
        preload_entity_sets: original.preload_entity_sets.dup,
      }

      configure do |config|
        config.adapter = adapter_name unless adapter_name.nil?
        config.strict_parsing = strict_parsing unless strict_parsing.nil?
        config.default_encoding = default_encoding unless default_encoding.nil?
      end

      yield if block_given?
    ensure
      configure do |config|
        config.adapter = saved_values[:adapter]
        config.strict_parsing = saved_values[:strict_parsing]
        config.default_encoding = saved_values[:default_encoding]
        config.default_indent = saved_values[:default_indent]
        config.default_line_ending = saved_values[:default_line_ending]
        config.entity_load_mode = saved_values[:entity_load_mode]
        config.restore_entities = saved_values[:restore_entities]
        config.namespace_validation_mode = saved_values[:namespace_validation_mode]
        config.entity_restoration_mode = saved_values[:entity_restoration_mode]
        config.preload_entity_sets = saved_values[:preload_entity_sets]
      end
    end

    def preprocess_entities(xml)
      Adapter::Base.preprocess_entities(xml)
    end

    def restore_entities(text)
      Adapter::Base.restore_entities(text)
    end
  end

  autoload :VERSION, "moxml/version"
  autoload :Config, "moxml/config"
  autoload :Context, "moxml/context"
  autoload :Node, "moxml/node"
  autoload :NodeSet, "moxml/node_set"
  autoload :Document, "moxml/document"
  autoload :Element, "moxml/element"
  autoload :Text, "moxml/text"
  autoload :Cdata, "moxml/cdata"
  autoload :Comment, "moxml/comment"
  autoload :Attribute, "moxml/attribute"
  autoload :AttributeResolver, "moxml/attribute_resolver"
  autoload :ProcessingInstruction, "moxml/processing_instruction"
  autoload :Declaration, "moxml/declaration"
  autoload :Namespace, "moxml/namespace"
  autoload :Doctype, "moxml/doctype"
  autoload :EntityReference, "moxml/entity_reference"
  autoload :Builder, "moxml/builder"
  autoload :Entity, "moxml/entity"
  autoload :EntityRegistry, "moxml/entity_registry"
  autoload :NativeAttachment, "moxml/native_attachment"
  autoload :XmlUtils, "moxml/xml_utils"
  autoload :XmlEmitter, "moxml/xml_emitter"
  autoload :Adapter, "moxml/adapter"
  autoload :XPath, "moxml/xpath"
  autoload :SAX, "moxml/sax"
  autoload :Signature, "moxml/signature"
  autoload :C14n, "moxml/c14n"

  # Error hierarchy — each subclass autoloads from the same file
  autoload :Error, "moxml/error"
  autoload :NotImplementedError, "moxml/error"
  autoload :ValidationError, "moxml/error"
  autoload :ParseError, "moxml/error"
  autoload :DocumentStructureError, "moxml/error"
  autoload :NamespaceError, "moxml/error"
  autoload :EntityDataError, "moxml/error"
  autoload :XPathError, "moxml/error"
  autoload :AdapterError, "moxml/error"
end
