# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      module DocumentParts
        # Issue #134: deterministic release of the C tree. The binding
        # clears its wrapper cache and raises UseAfterFreeError on
        # later access; moxml-side attachments for the document are
        # swept too (the context wrapper identity map self-cleans via
        # its size valve).
        DOCUMENT_ATTACHMENT_KEYS = %i[
          entity_markers doc_pi_nodes declaration doctype
          had_source_declaration document_text
        ].freeze

        def free_document(native)
          DOCUMENT_ATTACHMENT_KEYS.each { |key| attachments.delete(native, key) }
          native.free
          nil
        end

        def assemble_document_children(doc)
          children = []

          native_doctype = doc.doctype
          children << native_doctype if native_doctype

          doctype_wrapper = attachments.get(doc, :doctype)
          children << doctype_wrapper if doctype_wrapper

          if DOC_NODE_SUPPORTED
            # The libxml2-model document node lists prolog PIs/comments,
            # the root, and epilog PIs/comments in document order —
            # the Nokogiri-shaped contract, epilog anchoring included
            # (issue #130). Built (programmatic) documents are not yet
            # fully reflected by the node (binding gap: an attached
            # root does not appear); document_node_children answers
            # nil there for the legacy parts path.
            doc_children = document_node_children(doc)
            if doc_children
              children.concat(doc_children)
            else
              children.concat(document_pi_nodes(doc))
              children << doc.root if doc.root
            end
          else
            # Legacy path: document-level PIs live outside the element
            # tree in a flat pre-root list (libleptris < 1.9.7 C
            # model); epilog anchoring is not representable there.
            children.concat(document_pi_nodes(doc))

            children << doc.root if doc.root
          end

          texts = attachments.get(doc, :document_text)
          children.concat(texts) if texts
          children
        end

        # Document-level PI pseudo-nodes, materialized once from the C
        # list and cached per document: children and serialization read
        # the same objects, so wrapper mutations round-trip. Build the
        # cache BEFORE appending a PI with add_pi, or the C-side
        # addition would be double-counted.
        # The document node's children, or nil when the node does not
        # reflect reality: parsed documents always list the root
        # element among their children, but programmatically built
        # ones do not (binding gap) — those keep the legacy parts
        # path.
        def document_node_children(doc)
          doc_children = doc.children.to_a
          has_root = doc_children.any?(::Leptris::XML::Element)
          return doc_children if has_root
          return doc_children if doc.root.nil?

          nil
        end

        def document_pi_nodes(doc)
          attachments.get(doc, :doc_pi_nodes) || begin
            nodes = doc.processing_instructions.map do |(target, data)|
              CustomizedLeptris::DocumentPI.new(target, data, doc)
            end
            attachments.set(doc, :doc_pi_nodes, nodes)
            nodes
          end
        end

        def add_document_child(doc, child)
          case child
          when CustomizedLeptris::Declaration
            child.parent_doc = doc
            attachments.set(doc, :declaration, child)
          when CustomizedLeptris::Doctype
            child.parent_doc = doc
            attachments.set(doc, :doctype, child)
          when ::Leptris::XML::DocType
            raise Moxml::DocumentStructureError.new(
              "libleptris does not support attaching a native DocType to a document",
            )
          when ::Leptris::XML::Element
            doc.root = child
          when ::Leptris::XML::ProcessingInstruction
            document_pi_nodes(doc)
            doc.add_pi(child.target, child.content.to_s)
            document_pi_nodes(doc) << CustomizedLeptris::DocumentPI.new(
              child.target, child.content.to_s, doc
            )
          when CustomizedLeptris::DocumentPI
            document_pi_nodes(doc)
            doc.add_pi(child.target, child.data)
            document_pi_nodes(doc) << child
          when ::Leptris::XML::Text
            texts = attachments.get(doc, :document_text) || []
            texts << child
            attachments.set(doc, :document_text, texts)
            child
          else
            raise Moxml::DocumentStructureError.new(
              "Unsupported document child: #{child.class}",
            )
          end
          child
        end

        # Documents compose from their parts: the native serializer
        # only walks the root subtree, so declaration, DOCTYPE, PIs and
        # document-level text are assembled around it explicitly.
        def serialize_document(doc, options)
          # Nokogiri's document shape: every top-level part is
          # newline-terminated, at any indent — declaration, DOCTYPE,
          # document PIs, the root element, trailing newline after it.
          # Document-level text is content, not structure: no added
          # newline.
          parts = []

          include_decl = !options[:no_declaration] && options.fetch(:declaration) do
            document_has_declaration?(doc)
          end
          if include_decl
            declaration = attachments.get(doc, :declaration)
            parts << (declaration ? declaration.to_xml : default_declaration_xml(doc, options)) << "\n"
          end

          doctype = attachments.get(doc, :doctype)
          parts << doctype.to_xml << "\n" if doctype

          native = native_doctype_xml(doc)
          parts << native << "\n" if native

          if DOC_NODE_SUPPORTED
            # The libxml2-model document node: prolog PIs/comments,
            # the root, epilog PIs/comments — in document order, so
            # epilog parts serialize after the root (issue #130).
            doc_children = document_node_children(doc)
            if doc_children
              doc_children.each { |child| parts << raw_serialize(child, options) << "\n" }
            else
              document_pi_nodes(doc).each { |pi| parts << pi.to_xml << "\n" }
              parts << raw_serialize(doc.root, options) << "\n" if doc.root
            end
          else
            document_pi_nodes(doc).each { |pi| parts << pi.to_xml << "\n" }

            parts << raw_serialize(doc.root, options) << "\n" if doc.root
          end

          texts = attachments.get(doc, :document_text)
          texts&.each { |text| parts << XmlEmitter.escape_text(text.content.to_s) }

          parts.join
        end

        def native_doctype_xml(doc)
          dt = doc.doctype
          return nil unless dt

          subset = dt.internal_subset if dt.class.method_defined?(:internal_subset)
          XmlEmitter.doctype_xml(dt.root_name, dt.public_id, dt.system_id, subset)
        end

        def default_declaration_xml(doc, options)
          encoding = options[:encoding] || doc.encoding
          encoding = "UTF-8" if encoding.to_s.empty?
          XmlEmitter.declaration_xml("1.0", encoding, nil)
        end

        def document_has_declaration?(native)
          return false unless native.is_a?(::Leptris::XML::Document)

          return true if attachments.get(native, :declaration)

          attachments.get(native, :had_source_declaration) ? true : false
        end

        def marker_text_for(parent, name)
          return nil unless parent.is_a?(::Leptris::XML::Element)

          marker = "#{Entity::MARKER}#{name};"
          parent.children.to_a.find do |child|
            child.is_a?(::Leptris::XML::Text) && child.content == marker
          end
        end
      end
    end
  end
end
