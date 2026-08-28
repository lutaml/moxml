# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      module Materialize
        # Bulk materialization (issue #132): leptris_node_traverse
        # walks the subtree with one FFI call; the only per-node cost
        # is the C->Ruby callback and the property reads below. No
        # Moxml::Node or Attribute wrapper is allocated.
        def bulk_materialize?
          true
        end

        def materialize_records(native, &block)
          doc = native.is_a?(::Leptris::XML::Document) ? native : native.document
          # Marker-bearing text needs the split pipeline (children-level
          # ER expansion); the bulk path has no marker handling.
          return nil if doc.nil? || attachments.get(doc, :entity_markers)

          # On bindings whose traverse follows the document chain
          # (leptris 1.9.28–1.9.31), element materialize falls back to
          # the generic wrapper walk — only document materialization
          # can filter safely there (issue #140).
          root = if native.is_a?(::Leptris::XML::Document)
                   doc.root
                 else
                   return nil unless TRAVERSE_SUBTREE_BOUNDED

                   native
                 end
          return nil if root.nil?

          depth_memo = {}.compare_by_identity
          root.traverse do |node|
            depth = material_depth_in_subtree(node, root, depth_memo)
            next if depth.nil?

            record = case node
                     when ::Leptris::XML::Element
                       element_material_record(node, depth)
                     when ::Leptris::XML::CDATA
                       # CDATA < Text in the binding: this arm must come
                       # first or CDATA content reports as text.
                       text_material_record(:cdata, node.content, depth)
                     when ::Leptris::XML::Text
                       text_material_record(:text, node.content, depth)
                     when ::Leptris::XML::Comment
                       text_material_record(:comment, node.content, depth)
                     when ::Leptris::XML::ProcessingInstruction
                       text_material_record(:processing_instruction, node.content, depth)
                         .merge(qname: node.target)
                     end
            yield(record) if record
          end
          true
        end

        def element_material_record(node, depth)
          attributes = node.each_attribute.map do |attr|
            # Local name + separate prefix, matching the generic
            # path's resolver semantics (moxml's canonical shape).
            name = attr.name
            prefix = attr.prefix
            name = name.split(":", 2)[1] || name if prefix
            [name, attr.value, attr.namespace_uri, prefix]
          end
          ns = node.namespace
          # Own declarations only — same shape as the generic
          # path's Element#declared_namespaces (issue #138).
          decls = node.namespace_definitions.map { |d| [d.prefix, d.href] }
          Materializer::Record.element(
            qname: node.name,
            prefix: node.prefix,
            namespace_uri: ns&.href,
            namespaces: decls.empty? ? Materializer::EMPTY_ATTRIBUTES : decls,
            attributes: attributes,
            depth: depth,
          )
        end

        def text_material_record(kind, text, depth)
          Materializer::Record.text(kind: kind, text: text, depth: depth)
        end

        # Depth relative to the subtree root, or nil when the node
        # lies outside it (traverse follows the document chain since
        # leptris 1.9.28, so epilog siblings can appear in the
        # stream). Binding wrappers are address-stable and #parent is
        # memoized, so each edge resolves once through the
        # identity-keyed memo.
        def material_depth_in_subtree(node, root, memo)
          memo[node] ||= if node.equal?(root)
                           0
                         else
                           parent = node.parent
                           if parent.nil? || parent.is_a?(::Leptris::XML::Document)
                             nil
                           else

                             parent_depth = material_depth_in_subtree(parent, root, memo)
                             parent_depth.nil? ? nil : parent_depth + 1

                           end
                         end
        end
      end
    end
  end
end
