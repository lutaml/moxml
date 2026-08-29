# frozen_string_literal: true

module Moxml
  # Flattened subtree records for conversion-style consumers
  # (issue #132): one record per node, emitted in post-order (children
  # before parents — build with a stack), carrying everything a
  # consumer tree needs without allocating Moxml::Node or
  # Moxml::Attribute wrappers.
  #
  # Two emission forms share one walk (issue #143):
  #
  #   document.materialize { |record| ... }     # Hash snapshot per node
  #   document.materialize.to_a                 # Enumerator of snapshots
  #   document.materialize_fields { |kind, qname, prefix, namespace_uri,
  #                                  namespaces, attributes, text, depth| }
  #
  # materialize_fields is the conversion hot path: the two list
  # arguments are flat reused buffers — attributes stride 4 (name,
  # value, namespace_uri, prefix), namespaces stride 2 (prefix, uri;
  # nil prefix = default) — valid only inside the block. Copy anything
  # you intend to keep, or use materialize, whose records are
  # independent Hash snapshots.
  #
  # Record shape (both forms):
  #   kind: :element|:text|:cdata|:comment|:processing_instruction,
  #   qname: "tag"|"pi-target"|nil, prefix: "p"|nil,
  #   namespace_uri: "urn:x"|nil,
  #   namespaces: [[prefix, uri], ...],        # element's OWN declarations
  #   attributes: [[name, value, namespace_uri, prefix], ...],
  #   text: String|nil, depth: Integer
  #
  # Adapters with a bulk path (leptris: one leptris_node_traverse FFI
  # call for the whole subtree, reading properties straight off the C
  # handles) answer bulk_materialize?; the others walk the wrapper
  # tree generically. Both emit identical streams — spec-pinned.
  module Materializer
    # Shared frozen empty list for records with no list fields;
    # adapter bulk paths yield it too.
    EMPTY_ATTRIBUTES = [].freeze

    # The two flat, reused field buffers a materialize_fields block
    # receives (issue #143). One instance streams an entire subtree;
    # both arrays are cleared and refilled per element record.
    class Buffers
      attr_reader :attributes, :namespaces

      def initialize
        @attributes = []
        @namespaces = []
      end
    end

    # Builds the Hash snapshot form from the field stream — the one
    # place the eight-key record shape is materialized.
    module Record
      module_function

      def from_fields(kind, qname, prefix, namespace_uri, namespaces,
                      attributes, text, depth)
        {
          kind: kind,
          qname: qname,
          prefix: prefix,
          namespace_uri: namespace_uri,
          namespaces: group_flat(namespaces, 2),
          attributes: group_flat(attributes, 4),
          text: text,
          depth: depth,
        }
      end

      def group_flat(flat, stride)
        return EMPTY_ATTRIBUTES if flat.empty?

        flat.each_slice(stride).to_a
      end
    end

    module_function

    # Hash-snapshot form: every record is an independent Hash.
    def materialize(node, &block)
      return enum_for(:materialize, node) unless block

      materialize_fields(node) do |kind, qname, prefix, namespace_uri, namespaces, attributes, text, depth|
        yield(Record.from_fields(kind, qname, prefix, namespace_uri,
                                 namespaces, attributes, text, depth))
      end
    end

    # Zero-allocation streaming form — see the module docs. Requires
    # a block: the reused buffers are only valid inside it.
    def materialize_fields(node, buffers = Buffers.new, &block)
      raise ArgumentError, "materialize_fields requires a block" unless block

      adapter = node.context.config.adapter
      if adapter.bulk_materialize? &&
          adapter.materialize_fields(node.native, buffers, &block)
        return
      end

      walk_fields(node, 0, buffers, &block)
    end

    # Generic post-order walk over the wrapper tree. Works on every
    # adapter; the fast bulk path exists where the engine offers one.
    def walk_fields(node, depth, buffers, &block)
      case node
      when Element
        node.children.each { |child| walk_fields(child, depth + 1, buffers, &block) }
        fill_element_buffers(node, buffers)
        ns = node.namespace
        yield(:element, node.name, node.namespace_prefix, ns&.uri,
              buffers.namespaces, buffers.attributes, nil, depth)
      when Text
        yield(:text, nil, nil, nil, EMPTY_ATTRIBUTES, EMPTY_ATTRIBUTES,
              node.content, depth)
      when Cdata
        yield(:cdata, nil, nil, nil, EMPTY_ATTRIBUTES, EMPTY_ATTRIBUTES,
              node.content, depth)
      when Comment
        yield(:comment, nil, nil, nil, EMPTY_ATTRIBUTES, EMPTY_ATTRIBUTES,
              node.content, depth)
      when ProcessingInstruction
        yield(:processing_instruction, node.target, nil, nil,
              EMPTY_ATTRIBUTES, EMPTY_ATTRIBUTES, node.content, depth)
      when EntityReference
        yield(:entity_reference, node.name, nil, nil,
              EMPTY_ATTRIBUTES, EMPTY_ATTRIBUTES, "&#{node.name};", depth)
      end
    end

    def fill_element_buffers(element, buffers)
      attrs = buffers.attributes
      attrs.clear
      element.attributes.each do |attr|
        ns = attr.namespace
        attrs << attr.name << attr.value << ns&.uri << ns&.prefix
      end

      ns_buf = buffers.namespaces
      ns_buf.clear
      # declared_namespaces: the element's OWN declarations ([prefix,
      # uri] pairs; nil prefix = default), not the in-scope set —
      # enough for a consumer to rebuild scope while walking (#138).
      element.declared_namespaces.each do |prefix, uri|
        ns_buf << prefix << uri
      end
    end
  end
end
