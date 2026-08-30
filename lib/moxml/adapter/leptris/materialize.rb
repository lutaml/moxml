# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      module Materialize
        BINDING_FFI = ::Leptris::XML::FFI
        private_constant :BINDING_FFI

        EMPTY_FIELDS = Materializer::EMPTY_ATTRIBUTES

        NODE_ELEMENT = ::Leptris::XML::FFI::NODE_ELEMENT
        NODE_TEXT = ::Leptris::XML::FFI::NODE_TEXT
        NODE_COMMENT = ::Leptris::XML::FFI::NODE_COMMENT
        NODE_CDATA = ::Leptris::XML::FFI::NODE_CDATA
        NODE_PI = ::Leptris::XML::FFI::NODE_PI
        private_constant :NODE_ELEMENT, :NODE_TEXT, :NODE_COMMENT, :NODE_CDATA,
                         :NODE_PI

        # Reused child-pointer staging buffer capacity for the raw
        # pointer walk. Elements with more children grow the buffer
        # geometrically for the rest of the stream.
        CHILDREN_CAPACITY = 64
        private_constant :CHILDREN_CAPACITY

        # Bulk materialization (issues #132/#143): a Ruby-side
        # post-order recursion over RAW C pointers — no binding
        # wrapper per node, no per-node FFI callback, no depth memo
        # (depth is a recursion parameter), no record allocation.
        # Child lists arrive through the batch leptris_node_children
        # call; element fields are read straight off the C handles
        # (the binding's own first/next attribute iteration face),
        # skipping the per-attribute wrapper its public API
        # allocates. The unprefixed-attribute namespace read is
        # skipped because the answer is nil by definition
        # (no-namespace attributes).
        def bulk_materialize?
          true
        end

        def materialize_fields(native, buffers, &block)
          doc = native.is_a?(::Leptris::XML::Document) ? native : native.document
          # Marker-bearing text needs the split pipeline (children-level
          # ER expansion); the bulk path has no marker handling.
          return nil if doc.nil? || attachments.get(doc, :entity_markers)

          root_ptr = if native.is_a?(::Leptris::XML::Document)
                       doc.root&.c_ptr
                     else
                       native.c_ptr
                     end
          return nil unless root_ptr

          walk_fields(root_ptr, 0, buffers,
                      ::FFI::MemoryPointer.new(:pointer, CHILDREN_CAPACITY),
                      &block)
          true
        end

        def walk_fields(ptr, depth, buffers, child_buf, &block)
          f = BINDING_FFI
          capacity = CHILDREN_CAPACITY
          count = f.leptris_node_children(ptr, child_buf, capacity)
          while count == capacity
            capacity *= 4
            child_buf = ::FFI::MemoryPointer.new(:pointer, capacity)
            count = f.leptris_node_children(ptr, child_buf, capacity)
          end

          # Snapshot before recursing — the recursion reuses this
          # buffer for the next level's child list.
          children = child_buf.read_array_of_pointer(count)

          children.each do |child|
            case f.leptris_node_get_type(child)
            when NODE_ELEMENT
              walk_fields(child, depth + 1, buffers, child_buf, &block)
            when NODE_TEXT
              yield(:text, nil, nil, nil, EMPTY_FIELDS, EMPTY_FIELDS, f.leptris_text_node_get_content(child), depth + 1)
            when NODE_CDATA
              yield(:cdata, nil, nil, nil, EMPTY_FIELDS, EMPTY_FIELDS, f.leptris_cdata_node_get_content(child), depth + 1)
            when NODE_COMMENT
              yield(:comment, nil, nil, nil, EMPTY_FIELDS, EMPTY_FIELDS, f.leptris_comment_node_get_content(child), depth + 1)
            when NODE_PI
              yield(:processing_instruction, f.leptris_pi_node_get_target(child), nil, nil, EMPTY_FIELDS, EMPTY_FIELDS, f.leptris_pi_node_get_data(child), depth + 1)
            end
          end

          emit_element_fields(ptr, buffers, depth, &block)
        end

        def emit_element_fields(ptr, buffers, depth, &block)
          f = BINDING_FFI
          ns_buf = buffers.namespaces
          attrs_buf = buffers.attributes

          name = f.leptris_element_name(ptr)
          prefix = f.leptris_element_prefix(ptr)
          uri = f.leptris_element_namespace(ptr)
          uri = nil if uri && uri.empty?

          # Own declarations only — same shape as the generic path's
          # Element#declared_namespaces (issue #138).
          ns_buf.clear
          i = 0
          ns_count = f.leptris_element_namespace_count(ptr)
          while i < ns_count
            ns_buf << f.leptris_element_namespace_decl_prefix(ptr, i)
            ns_buf << f.leptris_element_namespace_decl_uri(ptr, i)
            i += 1
          end

          attrs_buf.clear
          attr = f.leptris_element_first_attribute(ptr)
          until attr.nil? || attr.null?
            attr_name = f.leptris_attribute_get_name(attr)
            attr_value = f.leptris_attribute_get_value(ptr, attr)
            colon = attr_name.index(":")
            if colon
              attr_prefix = attr_name[0, colon]
              # Local name + separate prefix, matching the generic
              # path's resolver semantics (moxml's canonical shape).
              attr_name = attr_name[(colon + 1)..]
              attr_uri = f.leptris_attribute_namespace_uri(attr)
            else
              attr_prefix = nil
              attr_uri = nil
            end
            attrs_buf << attr_name << attr_value << attr_uri << attr_prefix
            attr = f.leptris_attribute_next(attr)
          end

          yield(:element, name, prefix, uri, ns_buf, attrs_buf, nil, depth)
        end
      end
    end
  end
end
