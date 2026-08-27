# frozen_string_literal: true

module Moxml
  # Flattened subtree records for conversion-style consumers
  # (issue #132): one record per node, emitted in post-order (children
  # before parents — build with a stack), carrying everything a
  # consumer tree needs without allocating Moxml::Node or
  # Moxml::Attribute wrappers.
  #
  #   context.materialize(xml) { |r| ... }
  #   document.materialize.each { |r| ... }   # Enumerator
  #
  # Record shape:
  #   { kind: :element|:text|:cdata|:comment|:processing_instruction,
  #     qname: "tag"|"pi-target"|nil, prefix: "p"|nil,
  #     namespace_uri: "urn:x"|nil,
  #     attributes: [[name, value, namespace_uri, prefix], ...],
  #     text: String|nil, depth: Integer }
  #
  # Adapters with a bulk path (leptris: one leptris_node_traverse FFI
  # call for the whole subtree) answer bulk_materialize?; the others
  # walk the wrapper tree generically.
  module Materializer
    # Shared frozen empty attribute list for non-element records;
    # adapters' bulk paths reference it too.
    EMPTY_ATTRIBUTES = [].freeze

    module_function

    def materialize(node, &block)
      adapter = node.context.config.adapter
      return enum_for(:materialize, node) unless block

      if adapter.bulk_materialize? && adapter.materialize_records(node.native, &block)
        return
      end

      walk(node, 0, &block)
    end

    # Generic post-order walk over the wrapper tree. Works on every
    # adapter; the fast bulk path exists where the engine offers one.
    def walk(node, depth, &block)
      case node
      when Element
        node.children.each { |child| walk(child, depth + 1, &block) }
        yield(element_record(node, depth))
      when Text
        yield(text_record(:text, node.content, depth))
      when Cdata
        yield(text_record(:cdata, node.content, depth))
      when Comment
        yield(text_record(:comment, node.content, depth))
      when ProcessingInstruction
        yield(text_record(:processing_instruction, node.content, depth).merge(qname: node.target))
      when EntityReference
        yield(text_record(:entity_reference, "&#{node.name};", depth).merge(qname: node.name))
      end
    end

    def element_record(element, depth)
      attributes = element.attributes.map do |attr|
        ns = attr.namespace
        [attr.name, attr.value, ns&.uri, ns&.prefix]
      end
      ns = element.namespace
      {
        kind: :element,
        qname: element.name,
        prefix: element.namespace_prefix,
        namespace_uri: ns&.uri,
        attributes: attributes,
        text: nil,
        depth: depth,
      }
    end

    def text_record(kind, text, depth)
      {
        kind: kind,
        qname: nil,
        prefix: nil,
        namespace_uri: nil,
        attributes: EMPTY_ATTRIBUTES,
        text: text,
        depth: depth,
      }
    end
  end
end
