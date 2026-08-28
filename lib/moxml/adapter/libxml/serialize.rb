# frozen_string_literal: true

module Moxml
  module Adapter
    class Libxml
      # Wire-format knowledge: the C-engine fast path with its guards,
      # the Ruby fallback walker family, namespace-aware emission, and
      # the ReDoS-hardened empty-element expansion.
      module Serialize
        # Possessive-quantifier form: no backtracking, so pathological
        # attribute content cannot blow up the expansion pass.
        EMPTY_ELEMENT_EXPANSION_RE = %r{
          <([A-Za-z_][\w.:-]*+)
          ((?:"[^"]*+"|'[^']*+'|[^<>"'/]++)*+)
          />
        }x
        private_constant :EMPTY_ELEMENT_EXPANSION_RE

        NON_WHITESPACE_RE = /\S/
        private_constant :NON_WHITESPACE_RE

        def serialize(node, options = {})
          # FIRST: Check if node is any kind of wrapper with custom to_xml
          if node.is_a?(CustomizedLibxml::Node) || node.is_a?(DoctypeWrapper)
            return node.to_xml
          end

          native_node = unpatch_node(node)
          return "" unless native_node

          if native_node.is_a?(::LibXML::XML::Document)
            output = +""

            # Check if we should include declaration
            # Priority: explicit no_declaration option > default (include)
            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  else
                                    # Default: include declaration
                                    true
                                  end

            if should_include_decl
              # Check if declaration was explicitly managed
              decl = attachments.get(native_node, :declaration)
              if decl
                # Only output declaration if it exists and wasn't removed
                output << decl.to_xml unless decl.removed
              else
                # No declaration stored - create default
                version = native_node.version || "1.0"
                encoding_val = options[:encoding] ||
                  encoding_to_string(native_node.encoding) ||
                  "UTF-8"

                # Don't add standalone="yes" by default - only if explicitly set
                decl = CustomizedLibxml::Declaration.new(
                  native_node,
                  version,
                  encoding_val,
                  nil, # No standalone by default
                )
                attachments.set(native_node, :declaration, decl)
                output << decl.to_xml
              end
            end

            # Add DOCTYPE if stored on document
            doctype_wrapper = attachments.get(native_node, :doctype)
            if doctype_wrapper
              output << "\n" unless output.empty?
              output << doctype_wrapper.to_xml
            end

            # Parse-time document-level parts live on the chain around
            # the root (prolog/epilog PIs and comments); programmatic
            # ones stay in attachments. The chain nodes serialize in
            # document order around the root output below.
            chain_pre = []
            chain_post = []
            if native_node.root
              past_root = false
              chain_node = native_node.child
              while chain_node
                case chain_node.node_type
                when ::LibXML::XML::Node::ELEMENT_NODE then past_root = true
                when ::LibXML::XML::Node::PI_NODE, ::LibXML::XML::Node::COMMENT_NODE
                  (past_root ? chain_post : chain_pre) << chain_node.to_s
                end
                chain_node = chain_node.next
              end
            end
            chain_pre.each do |part|
              output << "\n" unless output.empty?
              output << part
            end

            # Add document-level processing instructions if stored
            pis = attachments.get(native_node, :pis)
            if pis && !pis.empty?
              pis.each do |pi|
                output << "\n" unless output.empty?
                output << pi.to_xml
              end
            end

            # Add text nodes if stored (for documents without root)
            texts = attachments.get(native_node, :texts)
            if texts && !texts.empty?
              texts.each do |text|
                output << "\n" unless output.empty?
                output << text.to_xml
              end
            end

            if native_node.root
              indent_size = options[:indent].is_a?(Integer) && options[:indent].positive? ? options[:indent] : 0
              # `eref_active` is computed once here and threaded through the
              # recursion so that the per-element `attachments.key?` Monitor
              # sync only fires for docs that actually have entity refs.
              eref_active = entity_ref_registry(native_node).active?
              root_output = native_root_output(native_node, indent_size)
              root_output ||= serialize_element_with_namespaces(
                native_node.root,
                include_ns: true,
                indent_size: indent_size,
                depth: 0,
                eref_active: eref_active,
              )

              output << "\n" << root_output unless output.empty?
              output << root_output if output.empty?
            end

            unless chain_post.empty?
              output << "\n" unless output.empty?
              output << chain_post.join("\n") << "\n"
            end

            output
          else
            serialize_element_with_namespaces(native_node, include_ns: true)
          end
        end

        # Serialize the root subtree with libxml's C serializer plus
        # moxml-canonical corrections — roughly 25x faster and ~2600x
        # fewer allocations than the Ruby walker. Returns nil whenever
        # a guard says the walker is still required.
        def native_root_output(native_doc, indent_size)
          return nil unless indent_size == 2
          return nil if entity_ref_registry(native_doc).active?

          output = native_doc.root.to_s

          # The walker strips prefixed names on parsed namespaced
          # children; that behavior is load-bearing, so namespaced
          # output keeps the walker.
          return nil if output.include?("xmlns")

          # The native serializer escapes non-ASCII codepoints in
          # attribute values as numeric character references
          # (x="&#xA9;"); the walker emits literal UTF-8
          return nil if output.include?("&#x")

          # Layout: pull closing tags onto the last child's line
          output = output.gsub(/\n[ \t]*(<\/[\w.:-]+>)/, '\1')

          if output.include?("/>")
            # A literal "/>" inside a comment or CDATA section would be
            # falsely expanded — the segment-aware walker is correct here
            return nil if output.include?("<!--") || output.include?("<![CDATA[")

            output = output.gsub(EMPTY_ELEMENT_EXPANSION_RE, '<\1\2></\1>')
          end

          # Native escapes attribute apostrophes; moxml keeps them literal
          output.gsub("&apos;", "'")
        end

        def serialize_element(elem)
          output = "<#{elem.name}"

          # Add namespace definitions (only on this element, not ancestors)
          if elem.is_a?(::LibXML::XML::Node)
            seen_ns = {}
            elem.namespaces.each do |ns|
              prefix = ns.prefix
              uri = ns.href
              next if seen_ns.key?(prefix)

              seen_ns[prefix] = true
              output << if prefix.nil? || prefix.empty?
                          " xmlns=\"#{XmlEmitter.escape_attribute(uri)}\""
                        else
                          " xmlns:#{prefix}=\"#{XmlEmitter.escape_attribute(uri)}\""
                        end
            end
          end

          # Add attributes
          if elem.attributes?
            elem.each_attr do |attr|
              next if attr.name.start_with?("xmlns")

              # Include namespace prefix if attribute has one
              attr_name = if attr.ns&.prefix
                            "#{attr.ns.prefix}:#{attr.name}"
                          else
                            attr.name
                          end
              output << " #{attr_name}=\"#{XmlEmitter.escape_attribute(attr.value)}\""
            end
          end

          # Always use verbose format <tag></tag> for consistency with other adapters
          output << ">"
          if elem.children?
            elem.each_child do |child|
              # Skip whitespace-only text nodes
              next if blank_text_node?(child)

              output << serialize_node(child)
            end
          end

          # Append any EntityReference wrappers stored on the document
          doc = elem.doc
          entity_refs = entity_ref_registry(doc).refs_for(elem)
          entity_refs&.each { |ref| output << ref.to_xml }

          output << "</#{elem.name}>"

          output
        end

        def serialize_node(node)
          # Check if node is a wrapper with to_xml method
          case node
          when CustomizedLibxml::ProcessingInstruction,
               CustomizedLibxml::Comment,
               CustomizedLibxml::Cdata,
               CustomizedLibxml::Text,
               CustomizedLibxml::EntityReference
            return node.to_xml
          end

          case node.node_type
          when ::LibXML::XML::Node::ELEMENT_NODE
            serialize_element(node)
          when ::LibXML::XML::Node::TEXT_NODE
            XmlEmitter.escape_text(node.content)
          when ::LibXML::XML::Node::CDATA_SECTION_NODE
            "<![CDATA[#{node.content}]]>"
          when ::LibXML::XML::Node::COMMENT_NODE
            "<!-- #{node.content} -->"
          when ::LibXML::XML::Node::PI_NODE
            "<?#{node.name} #{node.content}?>"
          else
            node.to_s
          end
        end

        def serialize_element_with_namespaces(elem, include_ns: true,
                                               indent_size: 0, depth: 0,
                                               eref_active: nil)
          # Cache elem.name — it's a libxml C call we'd otherwise make
          # twice (open tag + close tag). Concat with `<<` instead of
          # `"<#{name}"` to avoid the interpolated intermediate string.
          name = elem.name
          output = +"<"
          output << name
          emit_namespace_definitions(output, elem, include_ns)
          emit_attributes(output, elem)

          # `eref_active` is precomputed at the top-level `serialize` call
          # and threaded down — when nil (top-level non-recursive call into
          # this method), look it up; when false, skip the per-element doc
          # attachment query that otherwise fires for every element under
          # Monitor#synchronize.
          eref_active = doc_eref_active?(elem.doc) if eref_active.nil?
          entity_refs, child_sequence = if eref_active
                                          lookup_entity_ref_serialization(elem)
                                        else
                                          [
                                            nil, nil
                                          ]
                                        end

          # Always use verbose format <tag></tag> for consistency with other adapters
          output << ">"

          if entity_refs && child_sequence
            emit_eref_interleaved_children(output, elem, entity_refs, child_sequence,
                                           indent_size, depth, eref_active: eref_active)
          elsif elem.children?
            emit_children_with_layout(output, elem, indent_size, depth,
                                      eref_active: eref_active)
          end

          output << "</" << name << ">"
          output
        end

        # Emit `xmlns`/`xmlns:foo` declarations onto `output`. On the root
        # (`include_ns: true`) we emit ALL definitions; on children we
        # emit only definitions that OVERRIDE a parent's same-prefix URI.
        # Skips the whole block when the element has no local definitions,
        # which is the common case for child elements in unnamespaced docs.
        def emit_namespace_definitions(output, elem, include_ns)
          return unless elem.is_a?(::LibXML::XML::Node)

          ns_list = elem.namespaces
          return unless ns_list.is_a?(::LibXML::XML::Namespaces)

          definitions = ns_list.definitions
          return if definitions.empty?

          parent_ns_defs = include_ns ? nil : parent_namespace_defs(elem)
          seen_ns = nil

          definitions.each do |ns|
            prefix = ns.prefix
            uri = ns.href
            next unless include_ns ||
              (parent_ns_defs&.key?(prefix) && parent_ns_defs[prefix] != uri)

            seen_ns ||= {}
            next if seen_ns.key?(prefix)

            seen_ns[prefix] = true
            output << format_ns_declaration(prefix, uri)
          end
        end

        def parent_namespace_defs(elem)
          parent = elem.parent
          return nil unless parent.is_a?(::LibXML::XML::Node)

          defs = {}
          parent.namespaces.each { |ns| defs[ns.prefix] = ns.href }
          defs
        end

        def format_ns_declaration(prefix, uri)
          if prefix.nil? || prefix.empty?
            " xmlns=\"#{XmlEmitter.escape_attribute(uri)}\""
          else
            " xmlns:#{prefix}=\"#{XmlEmitter.escape_attribute(uri)}\""
          end
        end

        def emit_attributes(output, elem)
          return unless elem.attributes?

          elem.each_attr do |attr|
            next if attr.name.start_with?("xmlns")

            attr_name = attr.ns&.prefix ? "#{attr.ns.prefix}:#{attr.name}" : attr.name
            output << " #{attr_name}=\"#{XmlEmitter.escape_attribute(attr.value)}\""
          end
        end

        # Returns [entity_refs, child_sequence] when the element has
        # interleaved entity references that the serializer needs to
        # weave back into the native child stream — otherwise [nil, nil].
        #
        # The caller is responsible for gating this with `eref_active`
        # (precomputed once per `serialize` call). When `eref_active` is
        # false this method is never entered, so the per-element doc
        # attachment query never fires.
        def lookup_entity_ref_serialization(elem)
          doc = elem.doc
          return [nil, nil] unless doc

          entity_ref_registry(doc).serialization_for(elem)
        end

        def emit_eref_interleaved_children(output, elem, entity_refs, child_sequence,
                                            indent_size, depth, eref_active:)
          native_children = collect_non_blank_children(elem)
          child_pad = indent_size.positive? ? " " * (indent_size * (depth + 1)) : nil
          eref_idx = 0
          native_idx = 0
          prev_block = true

          child_sequence.each do |type|
            case type
            when :native
              if native_idx < native_children.size
                child = native_children[native_idx]
                is_text_like = child.text? || child.cdata?
                if prev_block && !is_text_like
                  output << "\n"
                  output << child_pad if child_pad
                end
                prev_block = !is_text_like

                output << serialize_child_to_xml(
                  child, indent_size: indent_size, depth: depth,
                         eref_active: eref_active
                )
                native_idx += 1
              end
            when :eref
              if eref_idx < entity_refs.size
                output << entity_refs[eref_idx].to_xml
                eref_idx += 1
                prev_block = false
              end
            end
          end
        end

        def blank_text_node?(child)
          child.text? && blank_content?(child.content)
        end

        def blank_content?(content)
          content.nil? || !content.match?(NON_WHITESPACE_RE)
        end

        def collect_non_blank_children(elem)
          children = []
          return children unless elem.children?

          elem.each_child do |c|
            children << c unless blank_text_node?(c)
          end
          children
        end

        # Walk native children once and emit them with the same newline +
        # indentation layout the old `add_newlines_to_xml` + `indent_xml`
        # post-passes produced — but in a single recursion with no string
        # rescanning.
        #
        # Newline rule (matching `>(?=<(?!/))` with CDATA-placeholder
        # protection): emit `\n` + per-level padding before a child iff
        # the previous emitted sibling was block-level (ended with `>`)
        # AND the current sibling is block-level. Text and CDATA count
        # as text-like and suppress the newline on both sides (the
        # original CDATA placeholder broke the `>...<` adjacency
        # symmetrically).
        def emit_children_with_layout(output, elem, indent_size, depth,
                                       eref_active:)
          child_pad = indent_size.positive? ? " " * (indent_size * (depth + 1)) : nil
          prev_block = true

          elem.each_child do |child|
            # Cache text? — used twice per child (whitespace skip + is_text_like).
            # For element children (the common case) both calls return false, so
            # caching saves a libxml C call.
            is_text = child.text?
            next if is_text && blank_content?(child.content)

            is_text_like = is_text || child.cdata?
            if prev_block && !is_text_like
              output << "\n"
              output << child_pad if child_pad
            end
            prev_block = !is_text_like

            output << serialize_child_to_xml(child, indent_size: indent_size, depth: depth,
                                                    eref_active: eref_active)
          end
        end

        # Serialize one child node. Elements recurse into the layout-aware
        # path; non-element wrappers route through their own `to_xml`;
        # everything else falls through to the per-type serializer.
        # `indent_size:` and `depth:` are required to force callers to
        # decide whether the child should inherit the parent's indent
        # state — the entity-ref interleave path deliberately passes 0/0.
        #
        # Element fast-path checked first to avoid allocating a wrapper
        # we'd immediately throw away (elements always recurse on the
        # raw native node, not the wrapper). For a typical document this
        # skips wrapper allocation for the majority of children.
        def serialize_child_to_xml(child, indent_size:, depth:, eref_active:)
          if child.element?
            return serialize_element_with_namespaces(child, include_ns: false,
                                                            indent_size: indent_size, depth: depth + 1,
                                                            eref_active: eref_active)
          end

          wrapped_child = patch_node(child)
          if wrapped_child.is_a?(CustomizedLibxml::Node)
            wrapped_child.to_xml
          else
            serialize_node(child)
          end
        end
      end
    end
  end
end
