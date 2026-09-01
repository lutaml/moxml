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
          entity_markers declaration doctype
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

          # The libxml2-model document node lists prolog PIs/comments,
          # the root, and epilog PIs/comments in document order — the
          # Nokogiri-shaped contract, epilog anchoring included (issue
          # #130). Built documents reflect their parts immediately
          # since leptris-ruby 1.9.32 (leptris-ruby#91).
          children.concat(doc.children.to_a)

          texts = attachments.get(doc, :document_text)
          children.concat(texts) if texts
          children
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
            doc.add_pi(child.target, child.content.to_s)
          when CustomizedLeptris::DocumentPI
            doc.add_pi(child.target, child.data)
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
          fast = fast_document_output(doc, options)
          return fast if fast

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

          # The libxml2-model document node: prolog PIs/comments, the
          # root, epilog PIs/comments — in document order, so epilog
          # parts serialize after the root (issue #130).
          doc.children.each { |child| parts << raw_serialize(child, options) << "\n" }

          texts = attachments.get(doc, :document_text)
          texts&.each { |text| parts << XmlEmitter.escape_text(text.content.to_s) }

          parts.join
        end

        # Issue #158: the engine's whole-document serializer is one C
        # call; the composed path serializes the root through the
        # element face, which copies the subtree into a fresh document
        # on every call (~4.5x slower end to end). The engine's output
        # is byte-identical to the composed one EXCEPT epilog parts
        # glue directly to the root — so the fast path declines
        # whenever anything follows the root, any attachment overrides
        # a part, or the engine's declaration line differs from the
        # facade's canonical form (checked post-hoc: a source
        # declaration carrying standalone or another version would
        # diverge).
        def fast_document_output(doc, options)
          return nil unless LIBXML2_LAYOUT_PARITY
          return nil if attachments.get(doc, :declaration) ||
            attachments.get(doc, :doctype) ||
            attachments.get(doc, :document_text) ||
            attachments.get(doc, :entity_markers)

          include_decl = !options[:no_declaration] && options.fetch(:declaration) do
            document_has_declaration?(doc)
          end

          root_seen = false
          doc.children.each do |child|
            if child.is_a?(::Leptris::XML::Element)
              return nil if root_seen

              root_seen = true
            elsif root_seen
              # Epilog parts glue directly to the root in the engine's
              # document output — compose those.
              return nil
            end
          end

          # The engine's subset serializer mangles every declaration
          # after the first (leptris/leptris#687) — moxml's own
          # formatter is correct, so those compose until the probe
          # says the engine is fixed.
          dt = doc.doctype
          if !ENGINE_MULTI_DECL_SUBSET_OK && dt&.class&.method_defined?(:internal_subset) &&
              (subset = dt.internal_subset) && subset.scan("<!").size > 1
            return nil
          end

          kwargs = {
            indent: options.fetch(:indent, 0),
            no_decl: !include_decl,
            encoding: options[:encoding],
          }
          if INDENT_UNIT_SUPPORTED && options[:indent_text].is_a?(String)
            kwargs[:indent_text] = options[:indent_text]
          end
          output = doc.to_xml(**kwargs)
          return nil if output.nil? || output.empty?

          if include_decl && !output.start_with?(default_declaration_xml(doc, options))
            return nil
          end

          output << "\n" unless output.end_with?("\n")
          output
        end

        def native_doctype_xml(doc)
          dt = doc.doctype
          return nil unless dt

          subset = dt.internal_subset if dt.class.method_defined?(:internal_subset)
          subset = format_internal_subset(subset) if LIBXML2_LAYOUT_PARITY
          XmlEmitter.doctype_xml(dt.root_name, dt.public_id, dt.system_id, subset)
        end

        # libxml2's DTD dump layout (leptris/leptris#636): newline
        # after "[", one after every markup declaration, none after
        # comments (they glue to both neighbors); an empty subset
        # drops the brackets. Returns the INNER text for
        # XmlEmitter.doctype_xml, nil when there is nothing to emit.
        # The engine reports internal_subset as raw source text, so
        # the declarations are re-tokenized — quote-aware, since an
        # attribute default can contain ">".
        def format_internal_subset(subset)
          return nil if subset.nil? || subset.empty?

          out = +"\n"
          pos = 0
          length = subset.length
          while pos < length
            start = subset.index("<", pos)
            break if start.nil?

            terminator, skip = if subset[start, 4] == "<!--"
                                 ["-->", 4]
                               elsif subset[start, 2] == "<?"
                                 ["?>", 2]
                               else
                                 [nil, 0]
                               end
            if terminator
              stop = subset.index(terminator, start + skip)
              break if stop.nil?

              item_end = stop + terminator.length
            else
              item_end = markup_decl_end(subset, start)
              break if item_end.nil?
            end
            out << subset[start...item_end]
            # Comments carry no trailing newline; declarations do.
            out << "\n" unless subset[start, 4] == "<!--"
            pos = item_end
          end
          out == "\n" ? nil : out
        end

        # End index of a markup declaration starting at `start`:
        # the first ">" outside quotes.
        QUOTE_CHARS = ['"', "'"].freeze
        private_constant :QUOTE_CHARS

        def markup_decl_end(subset, start)
          quote = nil
          i = start
          length = subset.length
          while i < length
            ch = subset[i]
            if quote
              quote = nil if ch == quote
            elsif QUOTE_CHARS.include?(ch)
              quote = ch
            elsif ch == ">"
              return i + 1
            end
            i += 1
          end
          nil
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
