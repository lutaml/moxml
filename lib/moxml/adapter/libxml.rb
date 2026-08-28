# frozen_string_literal: true

return if RUBY_ENGINE == "opal"

require "libxml"

module Moxml
  module Adapter
    class Libxml < Base
      # DOCTYPE prolog sniffer; see parse for the index-then-match
      # strategy that keeps this off the hot path.
      DOCTYPE_RE = /<!DOCTYPE\s+([^\s>]+)(?:\s+PUBLIC\s+"([^"]+)"\s+"([^"]+)"|\s+SYSTEM\s+"([^"]+)")?\s*>/i
      private_constant :DOCTYPE_RE

      autoload :EntityRefRegistry, "moxml/adapter/libxml/entity_ref_registry"

      # Wrapper class to store DOCTYPE information
      class DoctypeWrapper
        attr_reader :native_doc
        attr_accessor :name, :external_id, :system_id

        def initialize(doc, name, external_id, system_id)
          @native_doc = doc
          @name = name
          @external_id = external_id
          @system_id = system_id
        end

        # Provide native method to match adapter pattern
        def native
          @native_doc
        end

        def to_xml
          XmlEmitter.doctype_xml(@name, @external_id, @system_id)
        end
      end

      # Mapping from libxml's integer node_type to our symbol — built once
      # at load so `node_type` can do a single hash lookup on the hot path
      # instead of a large case/when on every node.
      NATIVE_NODE_TYPE_MAP = {
        ::LibXML::XML::Node::ELEMENT_NODE => :element,
        ::LibXML::XML::Node::TEXT_NODE => :text,
        ::LibXML::XML::Node::CDATA_SECTION_NODE => :cdata,
        ::LibXML::XML::Node::COMMENT_NODE => :comment,
        ::LibXML::XML::Node::PI_NODE => :processing_instruction,
        ::LibXML::XML::Node::ATTRIBUTE_NODE => :attribute,
        ::LibXML::XML::Node::DTD_NODE => :doctype,
        ::LibXML::XML::Node::DOCUMENT_NODE => :document,
      }.freeze
      private_constant :NATIVE_NODE_TYPE_MAP

      autoload :Serialize, "moxml/adapter/libxml/serialize"

      WRAPPER_NODE_TYPE_MAP = {
        DoctypeWrapper => :doctype,
        CustomizedLibxml::Declaration => :declaration,
        CustomizedLibxml::Element => :element,
        CustomizedLibxml::Text => :text,
        CustomizedLibxml::Cdata => :cdata,
        CustomizedLibxml::Comment => :comment,
        CustomizedLibxml::ProcessingInstruction => :processing_instruction,
        CustomizedLibxml::EntityReference => :entity_reference,
      }.freeze
      private_constant :WRAPPER_NODE_TYPE_MAP

      extend Serialize

      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          doc.root = element
        end

        # libxml-ruby mints a fresh Ruby object for the same C node on
        # each access; the wrapper identity map would accumulate dead
        # entries without bound at full mutation throughput.
        def wrappers_recyclable?
          false
        end

        def parse(xml, options = {}, _context = nil)
          # LibXML doesn't preserve DOCTYPE during parsing, so we need to extract it manually
          xml_string = if xml.is_a?(String)
                         xml
                       elsif xml.is_a?(IO) || xml.is_a?(StringIO)
                         xml.read
                       else
                         xml.to_s
                       end

          # Preprocess entities before parsing.
          # This converts the string to UTF-8; LibXML will use the encoding
          # parameter or XML declaration for byte interpretation.
          xml_string = preprocess_entities(xml_string)

          # Extract DOCTYPE before parsing. Locate the literal first:
          # a plain memscan is ~2x cheaper than the regex's literal
          # prefix scan on doctype-less documents (the common case),
          # and matching from the found offset keeps captures
          # identical.
          doctype_idx = xml_string.index("<!DOCTYPE")
          doctype_match = if doctype_idx
                            xml_string.match(DOCTYPE_RE, doctype_idx)
                          end

          native_doc = begin
            # Handle both string and file inputs
            parser = ::LibXML::XML::Parser.string(xml_string)
            parser.parse
          rescue ::LibXML::XML::Error => e
            if options[:strict]
              line = e.line
              raise Moxml::ParseError.new(
                e.message,
                line: line,
                column: nil,
                source: xml_string[0..100],
              )
            end
            # Return empty document for non-strict mode
            create_document
          end

          # Store DOCTYPE if found
          if doctype_match
            name = doctype_match[1]
            external_id = doctype_match[2]
            system_id = doctype_match[3] || doctype_match[4]

            doctype_wrapper = DoctypeWrapper.new(
              native_doc,
              name,
              external_id,
              system_id,
            )
            attachments.set(native_doc, :doctype, doctype_wrapper)
          end

          ctx = _context || Context.new(:libxml)
          # Single parse path: wrap libxml's already-complete C-parsed tree
          # directly (same pattern as the other adapters).
          # Doctype/declaration/PI attachments set above remain on
          # native_doc, so the serialize path still sees them.
          #
          # restore_entities is handled as a post-processing case after
          # the wrap, NOT by branching into a different builder. This way
          # any new parse-time logic only has to be added to this one
          # path; the restoration walk is just one of potentially several
          # post-processing steps and doesn't fork the construction.
          doc = Document.new(native_doc, ctx)
          Entity::Restorer.new(doc).run if ctx.config.restore_entities
          doc
        end

        # SAX parsing implementation for LibXML
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          # Create bridge that translates LibXML SAX to Moxml SAX
          bridge = LibXMLSAXBridge.new(handler)

          # Create LibXML SAX parser
          parser = ::LibXML::XML::SaxParser.string(xml.to_s)

          # Set callbacks
          parser.callbacks = bridge

          # Parse
          parser.parse
        rescue ::LibXML::XML::Error => e
          line = e.line
          column = begin
            e.column
          rescue StandardError
            nil
          end
          error = Moxml::ParseError.new(e.message, line: line, column: column)
          handler.on_error(error)
        end

        def create_document(_native_doc = nil)
          ::LibXML::XML::Document.new
        end

        def create_native_element(name, _owner_doc = nil)
          ::LibXML::XML::Node.new(name.to_s)
        end

        def create_native_text(content, _owner_doc = nil)
          native = ::LibXML::XML::Node.new_text(content.to_s)
          CustomizedLibxml::Text.new(native)
        end

        def create_native_entity_reference(name)
          CustomizedLibxml::EntityReference.new(name)
        end

        def entity_reference_name(node)
          node.name if node.is_a?(CustomizedLibxml::EntityReference)
        end

        def create_native_cdata(content, _owner_doc = nil)
          native = ::LibXML::XML::Node.new_cdata(content.to_s)
          CustomizedLibxml::Cdata.new(native)
        end

        def create_native_comment(content, _owner_doc = nil)
          native = ::LibXML::XML::Node.new_comment(content.to_s)
          CustomizedLibxml::Comment.new(native)
        end

        def create_native_processing_instruction(target, content)
          native = ::LibXML::XML::Node.new_pi(target.to_s, content.to_s)
          CustomizedLibxml::ProcessingInstruction.new(native)
        end

        def create_native_declaration(version, encoding, standalone)
          doc = create_document
          # Return a Declaration wrapper with explicit parameters
          CustomizedLibxml::Declaration.new(doc, version, encoding, standalone)
        end

        def create_native_doctype(name, external_id, system_id)
          # LibXML::XML::Dtd.new has bizarre parameter order, so we just
          # store values directly in our wrapper
          DoctypeWrapper.new(create_document, name.to_s, external_id&.to_s,
                             system_id&.to_s)
        end

        def node_type(node)
          return :unknown unless node

          # Fast path: native libxml nodes are the vast majority during
          # parse traversal (wrapping visits raw libxml children).
          # Skip the wrapper checks below for them.
          if node.is_a?(::LibXML::XML::Node)
            return NATIVE_NODE_TYPE_MAP[node.node_type] || :unknown
          end
          return :document if node.is_a?(::LibXML::XML::Document)

          wrapper_type = WRAPPER_NODE_TYPE_MAP[node.class]
          return wrapper_type if wrapper_type

          # Duck-typed fallback for libxml types that aren't ::Node
          # subclasses but still expose node_type (e.g. ::Attr).
          native = unpatch_node(node)
          return :unknown unless native.is_a?(::LibXML::XML::Node)

          NATIVE_NODE_TYPE_MAP[native.node_type] || :unknown
        end

        def node_name(node)
          native_node = unpatch_node(node)
          native_node&.name
        end

        def set_node_name(node, name)
          native_node = unpatch_node(node)
          native_node.name = name.to_s if native_node
        end

        def declaration_attribute(node, name)
          return nil unless node

          # Handle Declaration wrapper
          if node.is_a?(CustomizedLibxml::Declaration)
            case name
            when "version"
              node.version
            when "encoding"
              node.encoding
            when "standalone"
              node.standalone # Returns "yes", "no", or nil
            end
          else
            # Fallback for native documents
            case name
            when "version"
              node.version
            when "encoding"
              enc = node.encoding
              enc ? encoding_to_string(enc) : nil
            when "standalone"
              node.standalone? ? "yes" : nil
            end
          end
        end

        def set_declaration_attribute(node, name, value)
          return unless node

          # Handle Declaration wrapper
          return unless node.is_a?(CustomizedLibxml::Declaration)

          case name
          when "version"
            node.version = value
          when "encoding"
            node.encoding = value
          when "standalone"
            # Pass the value directly - Declaration handles the conversion
            node.standalone = value
          end

          # Native documents are read-only, do nothing for them
        end

        def children(node)
          native_node = unpatch_node(node)
          return [] unless native_node

          # Handle Document specially - it doesn't have children? method.
          # The binding's document chain lists prolog/epilog PIs and
          # comments around the root (Nokogiri-shaped contract); the
          # DOCTYPE attachment rides along first, mirroring the other
          # adapters.
          if native_node.is_a?(::LibXML::XML::Document)
            result = []
            has_native_doctype = false
            node = native_node.child
            while node
              has_native_doctype ||= node.node_type == ::LibXML::XML::Node::DTD_NODE
              result << patch_node(node)
              node = node.next
            end

            unless has_native_doctype
              doctype_wrapper = attachments.get(native_node, :doctype)
              result.unshift(doctype_wrapper) if doctype_wrapper
            end

            return result
          end

          result = []
          if native_node.children?
            native_node.each_child do |child|
              result << patch_node(child)
            end
          end

          # Include any EntityReference wrappers stored on the document
          doc = native_node.doc
          entity_refs = entity_ref_registry(doc).refs_for(native_node)
          result.concat(entity_refs) if entity_refs

          result
        end

        def parent(node)
          native_node = unpatch_node(node)
          parent_node = native_node&.parent
          parent_node ? patch_node(parent_node) : nil
        end

        def next_sibling(node)
          native_node = unpatch_node(node)
          current = native_node&.next
          while current
            # Skip whitespace-only text nodes
            break unless blank_text_node?(current)

            current = current.next
          end
          current ? patch_node(current) : nil
        end

        def previous_sibling(node)
          native_node = unpatch_node(node)
          current = native_node&.prev
          while current
            # Skip whitespace-only text nodes
            break unless blank_text_node?(current)

            current = current.prev
          end
          current ? patch_node(current) : nil
        end

        def document(node)
          native_node = unpatch_node(node)
          return nil unless native_node

          # Handle documents themselves
          return native_node if native_node.is_a?(::LibXML::XML::Document)

          # For other nodes, return their document
          native_node.doc
        end

        def root(document)
          native_doc = unpatch_node(document)
          native_doc&.root
        end

        def line_number(node)
          native = unpatch_node(node)
          native.is_a?(::LibXML::XML::Node) ? native.line_num : nil
        end

        def attributes(element)
          native_elem = unpatch_node(element)
          return [] unless native_elem
          unless native_elem.is_a?(::LibXML::XML::Node) && native_elem.element?
            return []
          end
          return [] unless native_elem.attributes?

          attrs = []
          native_elem.each_attr do |attr|
            attrs << attr unless attr.name.to_s.start_with?("xmlns")
          end
          attrs
        end

        def attribute_element(attr)
          attr&.parent
        end

        def attribute_namespace(attr)
          return nil unless attr
          return nil unless attr.is_a?(::LibXML::XML::Attr)

          attr.ns
        end

        def set_attribute(element, name, value)
          native_elem = unpatch_node(element)
          return unless native_elem

          name_str = name.to_s
          value_str = value.to_s

          # Check if attribute name contains namespace prefix
          if name_str.include?(":")
            prefix, local_name = name_str.split(":", 2)

            # Find the namespace with the given prefix
            ns = find_namespace_by_prefix(native_elem, prefix)

            if ns
              # LibXML::XML::Attr.new accepts namespace as third parameter
              # First remove existing attribute if present
              existing = native_elem.attributes.get_attribute(name_str)
              existing&.remove!

              # Create new attribute with namespace
              # Attr.new(node, name, value, ns)
              ::LibXML::XML::Attr.new(native_elem, local_name, value_str, ns)

              # Return the created attribute

            else
              # Namespace not found, set as regular attribute
              native_elem[name_str] = value_str
              native_elem.attributes.get_attribute(name_str)
            end
          else
            # node[]= is ambiguous when a namespace-bound attribute
            # shares the local name (it clobbers that attribute);
            # create or replace the no-namespace attribute explicitly.
            native_elem.each_attr do |attr|
              attr.remove! if !attr.ns && attr.name == name_str
            end if native_elem.attributes?
            ::LibXML::XML::Attr.new(native_elem, name_str, value_str)
          end
        end

        def get_attribute(element, name)
          native_elem = unpatch_node(element)
          return nil unless native_elem
          return nil unless native_elem.attributes?

          attr = native_elem.attributes.get_attribute(name.to_s)
          return nil unless attr

          # Extend the attribute with to_xml method for proper escaping
          attr.define_singleton_method(:to_xml) do
            escaped = value.to_s
              .gsub("&", "&amp;")
              .gsub("<", "&lt;")
              .gsub(">", "&gt;")
              .gsub("\"", "&quot;")
            "#{name} = #{escaped}"
          end
          attr
        end

        def get_attribute_value(element, name)
          native_elem = unpatch_node(element)
          return nil unless native_elem

          name_s = name.to_s
          if name_s.include?(":")
            prefix, local_name = name_s.split(":", 2)
            # Try to find attribute by namespace
            if native_elem.attributes?
              native_elem.each_attr do |attr|
                if [local_name, name_s].include?(attr.name)
                  # Check if attribute's namespace matches the prefix
                  if attr.ns && attr.ns.prefix == prefix
                    return attr.value
                  elsif attr.name == name_s
                    # Fallback: attribute name includes the prefix
                    return attr.value
                  end
                end
              end
            end

            return nil
          end

          # Bare name: node[name_s] is ambiguous when a namespaced
          # attribute shares the local name (issue #94), so prefer the
          # namespace-less attribute explicitly.
          if native_elem.attributes?
            namespaced_value = nil
            native_elem.each_attr do |attr|
              next if attr.name.to_s.start_with?("xmlns")
              next unless attr.name == name_s

              if attr.ns.nil?
                return attr.value
              elsif namespaced_value.nil?
                namespaced_value = attr.value
              end
            end
            return namespaced_value unless namespaced_value.nil?
          end

          native_elem[name_s]
        end

        def remove_attribute(element, name)
          native_elem = unpatch_node(element)
          return unless native_elem
          return unless native_elem.attributes?

          attr = native_elem.attributes.get_attribute(name.to_s)
          attr&.remove!
        end

        def remove_attribute_native(attr)
          attr&.remove!
        end

        def set_attribute_name(attribute, new_name)
          # LibXML attributes cannot be renamed directly
          # We must work at the element level
          return unless attribute

          # Get values FIRST before any removal
          old_name = attribute.name
          value = attribute.value
          element = attribute.parent
          return unless element

          # Remove old attribute via element
          element.attributes.get_attribute(old_name)&.remove!

          # Add new attribute with same value
          element[new_name.to_s] = value

          # Return the new attribute
          element.attributes.get_attribute(new_name.to_s)
        end

        def add_child(element, child)
          return unless element && child

          # Unwrap both element and child
          native_elem = unpatch_node(element)
          native_child = unpatch_node(child)

          # EntityReference wrappers can't go in LibXML's native tree.
          # Store them on the document for interleaved serialization.
          if child.is_a?(CustomizedLibxml::EntityReference)
            doc = native_elem.is_a?(::LibXML::XML::Document) ? native_elem : native_elem.doc
            entity_ref_registry(doc).register(native_elem, child)
            return
          end

          # For LibXML: if parent has a DEFAULT namespace (nil/empty prefix) and child is an element without a namespace,
          # explicitly set the child's namespace to match the parent's for XPath compatibility
          # NOTE: Prefixed namespaces are NOT inherited, only default namespaces.
          #
          # Reorder cheap-first: skip the expensive `.namespaces` fetches
          # entirely for non-element children (text, comment, cdata, PI),
          # which is roughly 30-50% of adds in a typical doc.
          if native_child.is_a?(::LibXML::XML::Node) && native_child.element? &&
              native_elem.is_a?(::LibXML::XML::Node) && native_elem.namespaces&.namespace &&
              (!native_child.namespaces.namespace || native_child.namespaces.namespace.href.to_s.empty?)

            parent_ns = native_elem.namespaces.namespace
            # Only set child's namespace if parent's namespace is DEFAULT (nil or empty prefix)
            if parent_ns.prefix.nil? || parent_ns.prefix.to_s.empty?
              native_child.namespaces.namespace = parent_ns
            end
          end

          if native_elem.is_a?(::LibXML::XML::Document)
            # For Declaration wrappers, store them for serialization
            if child.is_a?(CustomizedLibxml::Declaration)
              attachments.set(native_elem, :declaration, child)
              # Also store reference to parent document in the declaration
              child.parent_doc = native_elem
              return
            end

            # For DOCTYPE wrappers, store them for serialization
            if child.is_a?(DoctypeWrapper)
              attachments.set(native_elem, :doctype, child)
              return
            end

            # For document-level PIs, store them for serialization
            if child.is_a?(CustomizedLibxml::ProcessingInstruction)
              pis = attachments.get(native_elem, :pis) || []
              pis << child
              attachments.set(native_elem, :pis, pis)
              return
            end

            # For text nodes added to document, store them for serialization
            # Documents can't have text children in LibXML
            if child.is_a?(CustomizedLibxml::Text)
              texts = attachments.get(native_elem, :texts) || []
              texts << child
              attachments.set(native_elem, :texts, texts)
              return
            end

            # For documents, check if adding the first root element
            if native_elem.root.nil? && node_type(native_child) == :element
              # Set as root element
              native_elem.root = native_child
              # Flag for actual_native to refresh the wrapper's native reference
              attachments.set(native_elem, :_pending_root_refresh,
                              native_child.object_id)
            elsif native_elem.root
              # Document has root, add to it instead
              import_and_add(native_elem.doc, native_elem.root, native_child)
            end
          else
            import_and_add(native_elem.doc, native_elem, native_child)
            doc = native_elem.doc || native_elem
            entity_ref_registry(doc).append_native(native_elem)
          end
        end

        def append_child_sequence(element, type)
          seq = attachments.get(element, :child_sequence) || []
          seq << type
          attachments.set(element, :child_sequence, seq)
        end

        def add_previous_sibling(node, sibling)
          return unless node && sibling

          native_node = unpatch_node(node)
          native_sibling = unpatch_node(sibling)

          # Special handling for document-level processing instructions
          # When adding a PI as sibling to root element, store it on document
          if sibling.is_a?(CustomizedLibxml::ProcessingInstruction) &&
              native_node.is_a?(::LibXML::XML::Node) && native_node.doc
            doc = native_node.doc
            pis = attachments.get(doc, :pis) || []
            pis << sibling
            attachments.set(doc, :pis, pis)
            return
          end

          native_node.prev = native_sibling
        end

        def add_next_sibling(node, sibling)
          return unless node && sibling

          native_node = unpatch_node(node)
          native_sibling = unpatch_node(sibling)
          native_node.next = native_sibling
        end

        def remove(node)
          # Handle Declaration wrapper - mark as removed on document
          if node.is_a?(CustomizedLibxml::Declaration)
            node.removed = true
            return
          end

          native_node = unpatch_node(node)
          native_node&.remove!
        end

        def replace(node, new_node)
          native_node = unpatch_node(node)
          native_new = unpatch_node(new_node)
          parent = native_node&.parent
          return unless parent && native_new

          # Special handling for text nodes - LibXML's sibling manipulation
          # doesn't work reliably for text nodes. Instead, use parent.content
          # for text-to-text replacement
          if native_node.text? && native_new.text?
            parent.content = native_new.content
            return
          end

          # Save the prev/next siblings before removing
          prev_sibling = native_node.prev
          next_sibling = native_node.next

          # Import if needed for cross-document operations
          parent_doc = parent.is_a?(::LibXML::XML::Node) ? parent.doc : nil

          # Use import_and_add to properly handle document adoption
          import_and_add(parent_doc, parent, native_new)

          # Now adjust the position - move new node to where old node was
          if prev_sibling
            # Insert after the previous sibling
            prev_sibling.next = native_new
          end
          if next_sibling
            # Insert before the next sibling
            next_sibling.prev = native_new
          end

          # Finally remove the old node
          native_node.remove!
        end

        def replace_children(element, children)
          native_elem = unpatch_node(element)
          return unless native_elem

          # Remove all existing children first
          native_elem.each_child(&:remove!)

          # Get the element's document for importing
          doc = native_elem.is_a?(::LibXML::XML::Node) ? native_elem.doc : nil

          children.each do |c|
            native_c = unpatch_node(c)

            # Use import_and_add helper which handles all the edge cases
            import_and_add(doc, native_elem, native_c)
          end
        end

        def text_content(node)
          return "" if node.is_a?(CustomizedLibxml::EntityReference)

          native_node = unpatch_node(node)
          return nil unless native_node

          native_node.content
        end

        def inner_text(node)
          native_node = unpatch_node(node)
          return "" unless native_node
          return "" unless native_node.children?

          result = []
          native_node.each_child do |child|
            result << child.content if child.text?
          end
          result.join
        end

        def set_text_content(node, content)
          native_node = unpatch_node(node)
          return unless native_node.is_a?(::LibXML::XML::Node)

          # Text wrapper: swap with new_text to preserve verbatim storage.
          # Element wrapper: let libxml manage the child text node.
          if native_node.text?
            replace_native_verbatim(node, ::LibXML::XML::Node.new_text(content.to_s))
          else
            native_node.content = content.to_s
          end
        end

        # Replace `old_native` with `fresh`, preserving position. Both
        # neighbor pointers are set explicitly to match `replace`'s
        # semantics (see #replace above).
        def swap_native_in_place(old_native, fresh)
          parent = old_native.parent
          return if parent.nil?

          prev_sibling = old_native.prev
          next_sibling = old_native.next
          old_native.remove!
          prev_sibling.next = fresh if prev_sibling
          next_sibling.prev = fresh if next_sibling
          parent << fresh unless prev_sibling || next_sibling
        end
        private :swap_native_in_place

        # libxml-ruby's node.content= pre-escapes; building a fresh node via
        # new_<kind> stores content verbatim. Swap in place and re-point the
        # wrapper.
        def replace_native_verbatim(node, fresh)
          native = unpatch_node(node)
          return unless native.is_a?(::LibXML::XML::Node)

          swap_native_in_place(native, fresh)
          node.replace_native!(fresh) if node.is_a?(CustomizedLibxml::Node)
        end
        private :replace_native_verbatim

        def cdata_content(node)
          # libxml stores CDATA payload verbatim; no decoding needed.
          unpatch_node(node)&.content
        end

        def set_cdata_content(node, content)
          replace_native_verbatim(node, ::LibXML::XML::Node.new_cdata(content.to_s))
        end

        def comment_content(node)
          native_node = unpatch_node(node)
          native_node&.content
        end

        def set_comment_content(node, content)
          replace_native_verbatim(node, ::LibXML::XML::Node.new_comment(content.to_s))
        end

        def processing_instruction_target(node)
          native_node = unpatch_node(node)
          native_node&.name
        end

        def processing_instruction_content(node)
          # XML 1.0 §2.6: PI content is verbatim — no entity resolution.
          unpatch_node(node)&.content
        end

        def set_processing_instruction_content(node, content)
          native_node = unpatch_node(node)
          return unless native_node.is_a?(::LibXML::XML::Node)

          replace_native_verbatim(
            node,
            ::LibXML::XML::Node.new_pi(native_node.name, content.to_s),
          )
        end

        def create_native_namespace(element, prefix, uri)
          native_elem = unpatch_node(element)
          return nil unless native_elem

          ns = ::LibXML::XML::Namespace.new(
            native_elem,
            prefix.to_s.empty? ? nil : prefix.to_s,
            uri.to_s,
          )

          # For default namespace (nil/empty prefix), set it as the element's namespace
          native_elem.namespaces.namespace = ns if prefix.to_s.empty?

          ns
        end

        def set_namespace(element, ns)
          native_elem = unpatch_node(element)
          return element unless native_elem

          native_elem.namespaces.namespace = ns if ns
          element
        end

        def namespace(element)
          native_elem = unpatch_node(element)
          return nil unless native_elem

          # Return ONLY the element's own namespace
          # Do NOT inherit parent namespaces (prefixed namespaces are NOT inherited)
          # Only default namespaces are inherited during element creation by LibXML
          native_elem.namespaces&.namespace
        end

        def namespace_prefix(namespace)
          namespace&.prefix
        end

        def namespace_uri(namespace)
          namespace&.href
        end

        def namespace_definitions(node)
          native_node = unpatch_node(node)
          return [] unless native_node
          return [] unless native_node.is_a?(::LibXML::XML::Node)

          namespaces = native_node.namespaces
          return [] unless namespaces

          namespace_list =
            if namespaces.is_a?(::LibXML::XML::Namespaces)
              namespaces.definitions
            else
              namespaces
            end

          namespace_list.to_a
        end

        # Doctype accessor methods
        def doctype_name(native)
          # LibXML uses DoctypeWrapper which stores the values
          native.name
        end

        def doctype_external_id(native)
          native.external_id
        end

        def doctype_system_id(native)
          native.system_id
        end

        def xpath(node, expression, namespaces = nil)
          native_node = unpatch_node(node)
          return [] unless native_node

          # Build namespace context for LibXML
          # LibXML requires ALL prefixes in the XPath to be registered
          ns_context = build_xpath_namespaces(native_node, namespaces)

          found = if ns_context.empty?
                    native_node.find(expression)
                  else
                    native_node.find(expression, ns_context)
                  end

          # find returns an XPath::Object for node results, scalars for
          # count()/string()/boolean functions (adapter contract)
          return found if found.is_a?(Float) || found.is_a?(String) ||
            [true, false].include?(found)

          found.to_a.map { |n| patch_node(n) }
        rescue ::LibXML::XML::Error => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "LibXML",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = nil)
          results = xpath(node, expression, namespaces)
          results&.first
        end

        # Shallow duplication: copies the node itself (name, attrs, namespaces)
        # but NOT its descendants (deep duplication composes this).
        # walks the source tree and re-adds children one at a time via
        # add_child, so a deep copy here would be done only to be stripped
        # by replace_children, then rebuilt — O(N²) waste on parse.
        #
        # For callers that need a true deep copy (e.g. the import_and_add
        # fallback when LibXML can't move the subtree directly), use
        # deep_duplicate_node.
        def duplicate_node(node)
          return nil unless node

          native_node = unpatch_node(node)

          case node_type(node)
          when :doctype
            if node.is_a?(DoctypeWrapper)
              DoctypeWrapper.new(
                create_document,
                node.name,
                node.external_id,
                node.system_id,
              )
            else
              node
            end
          when :element
            # Public dup contract: a full deep copy of the subtree
            deep_duplicate_node(native_node)
          when :text
            ::LibXML::XML::Node.new_text(native_node.content)
          when :cdata
            ::LibXML::XML::Node.new_cdata(native_node.content)
          when :comment
            ::LibXML::XML::Node.new_comment(native_node.content)
          when :processing_instruction
            ::LibXML::XML::Node.new_pi(native_node.name, native_node.content)
          else
            native_node.dup
          end
        end

        def patches_children?
          true
        end

        def patch_node(node, _parent = nil)
          # Wrap native LibXML nodes in our wrapper classes
          return node if node.nil?
          return node if node.is_a?(CustomizedLibxml::Node)

          case node_type(node)
          when :element
            CustomizedLibxml::Element.new(node)
          when :text
            CustomizedLibxml::Text.new(node)
          when :cdata
            CustomizedLibxml::Cdata.new(node)
          when :comment
            CustomizedLibxml::Comment.new(node)
          when :processing_instruction
            CustomizedLibxml::ProcessingInstruction.new(node)
          else
            node
          end
        end

        def unpatch_node(node)
          # Unwrap to get native LibXML node
          case node
          when CustomizedLibxml::Node, CustomizedLibxml::Declaration, DoctypeWrapper
            node.native
          else
            node
          end
        end

        def has_declaration?(native_doc, wrapper)
          decl = attachments.get(native_doc, :declaration)
          if decl
            !decl.removed
          else
            wrapper.has_xml_declaration
          end
        end

        def remove_declaration(native_doc)
          decl = attachments.get(native_doc, :declaration)
          decl&.removed = true
        end

        # LibXML's doc.root= creates a new Ruby wrapper with different object_id.
        # Return the actual root node so attachments are stored on the correct object.
        def actual_native(child_native, parent_native)
          if parent_native.is_a?(::LibXML::XML::Document)
            pending = attachments.get(parent_native, :_pending_root_refresh)
            if pending && pending == child_native.object_id
              attachments.delete(parent_native, :_pending_root_refresh)
              return parent_native.root
            end
          end
          child_native
        end

        private

        def import_and_add(doc, element, child)
          return unless element && child

          # Always catch the cross-document error and import when needed
          begin
            element << child
          rescue ::LibXML::XML::Error => e
            # If we get a "different documents" error, we need to import or copy
            raise unless e.message.include?("different documents")

            # Get the target document - either from parameter or element
            target_doc = doc || (element.is_a?(::LibXML::XML::Node) ? element.doc : nil)

            if target_doc
              # Use deep import to ensure all descendants are included
              imported = target_doc.import(child, true)
              element << imported
            else
              # No target document - create a deep copy of the node instead
              # This handles the case where the element isn't attached to a document yet
              copied = deep_duplicate_node(child)
              element << copied
            end

            # Re-raise other errors
          end
        end

        def encoding_to_string(encoding)
          return nil unless encoding
          return encoding if encoding.is_a?(String)

          case encoding
          when ::LibXML::XML::Encoding::UTF_8
            "UTF-8"
          when ::LibXML::XML::Encoding::ISO_8859_1
            "ISO-8859-1"
          when ::LibXML::XML::Encoding::UTF_16LE
            "UTF-16LE"
          when ::LibXML::XML::Encoding::UTF_16BE
            "UTF-16BE"
          when ::LibXML::XML::Encoding::UCS_2
            "UCS-2"
          else
            "UTF-8"
          end
        end

        def string_to_encoding(str)
          return nil unless str

          case str.upcase.tr("-", "_")
          when "UTF_8", "UTF8"
            ::LibXML::XML::Encoding::UTF_8
          when "ISO_8859_1", "ISO88591"
            ::LibXML::XML::Encoding::ISO_8859_1
          when "UTF_16LE", "UTF16LE"
            ::LibXML::XML::Encoding::UTF_16LE
          when "UTF_16BE", "UTF16BE"
            ::LibXML::XML::Encoding::UTF_16BE
          else
            ::LibXML::XML::Encoding::UTF_8
          end
        end

        def doc_eref_active?(doc)
          entity_ref_registry(doc).active?
        end

        def entity_ref_registry(doc)
          EntityRefRegistry.new(attachments, doc)
        end

        # Regex used in place of `content.to_s.strip.empty?` for whitespace-only
        # text detection — `match?` allocates nothing while `.strip` makes a
        # throwaway copy of every text node's content on each visit.

        def collect_namespace_definitions(node)
          ns_defs = {}

          # Start from root to scan entire document
          root = if node.is_a?(::LibXML::XML::Document)
                   node.root
                 else
                   # Walk up to root first
                   current = node
                   current = current.parent while current.is_a?(::LibXML::XML::Node) && current.parent && !current.parent.is_a?(::LibXML::XML::Document)
                   current
                 end

          return ns_defs unless root

          # Recursively collect ALL namespace definitions from entire tree
          collect_ns_from_subtree(root, ns_defs)

          ns_defs
        end

        def collect_ns_from_subtree(node, ns_defs)
          # Collect namespaces defined on this node
          if node.is_a?(::LibXML::XML::Node)
            node.namespaces.each do |ns|
              prefix = ns.prefix
              uri = ns.href

              # For default namespace (nil/empty prefix), register as "xmlns"
              if prefix.nil? || prefix.empty?
                # Only register if we haven't seen a default namespace yet
                ns_defs["xmlns"] = uri unless ns_defs.key?("xmlns")
              else
                # Only register if we haven't seen this prefix yet
                ns_defs[prefix] = uri unless ns_defs.key?(prefix)
              end
            end
          end

          # Also check if this element has an active namespace (inherited or own)
          # This catches cases where elements inherit namespaces from parents
          if node.is_a?(::LibXML::XML::Node) && node.namespaces.is_a?(::LibXML::XML::Namespaces)
            active_ns = node.namespaces.namespace
            if active_ns
              prefix = active_ns.prefix
              uri = active_ns.href

              # Register the active namespace if not already registered
              if prefix.nil? || prefix.empty?
                ns_defs["xmlns"] = uri unless ns_defs.key?("xmlns")
              else
                ns_defs[prefix] = uri unless ns_defs.key?(prefix)
              end
            end
          end

          # Recursively collect from children
          return unless node.is_a?(::LibXML::XML::Node) && node.children?

          node.each_child do |child|
            collect_ns_from_subtree(child, ns_defs) if child.element?
          end
          ns_defs
        end

        def build_xpath_namespaces(node, user_namespaces)
          # Start with collected namespace definitions
          ns_context = collect_namespace_definitions(node)

          # Merge user-provided namespaces (they override collected ones)
          if user_namespaces && !user_namespaces.empty?
            ns_context = ns_context.merge(user_namespaces)
          end

          ns_context
        end

        def find_namespace_by_prefix(element, prefix)
          # Search element and ancestors for namespace with given prefix
          current = element
          while current
            if current.is_a?(::LibXML::XML::Node)
              current.namespaces.each do |ns|
                return ns if ns.prefix == prefix
              end
            end
            current = current.is_a?(::LibXML::XML::Node) ? current.parent : nil
          end
          nil
        end

        # Deep duplication for the rare `import_and_add` fallback (when
        # libxml refuses to move a subtree across documents AND no target
        # document is available). Walks the source subtree and rebuilds
        # it as document-independent nodes. The DocumentBuilder hot path
        # goes through the shallow `duplicate_node` instead.
        def deep_duplicate_node(node)
          return nil unless node

          native_node = unpatch_node(node)

          return duplicate_node(node) unless node_type(node) == :element

          new_node = shallow_duplicate_element(native_node)
          return new_node unless native_node.is_a?(::LibXML::XML::Node) && native_node.children?

          native_node.each_child do |child|
            next if blank_text_node?(child)

            new_node << deep_duplicate_node(child)
          end
          new_node
        end

        # Copies a single element: its name, its OWN namespace definitions,
        # the active default namespace, and its attributes. Children are NOT
        # duplicated — callers that need the subtree use deep_duplicate_node.
        def shallow_duplicate_element(native_node)
          new_node = ::LibXML::XML::Node.new(native_node.name)
          if native_node.is_a?(::LibXML::XML::Node)
            copy_element_namespaces(native_node,
                                    new_node)
          end
          if native_node.attributes?
            copy_element_attributes(native_node,
                                    new_node)
          end
          new_node
        end

        def copy_element_namespaces(src, dst)
          ns_list = src.namespaces
          ns_list.each do |ns|
            ::LibXML::XML::Namespace.new(dst, ns.prefix, ns.href)
          end

          own_ns = ns_list.namespace
          return unless own_ns

          dst.namespaces.each do |ns|
            next unless ns.prefix == own_ns.prefix && ns.href == own_ns.href

            dst.namespaces.namespace = ns
            break
          end
        end

        def copy_element_attributes(src, dst)
          src.each_attr do |attr|
            attr_name = attr.ns&.prefix ? "#{attr.ns.prefix}:#{attr.name}" : attr.name
            dst[attr_name] = attr.value
          end
        end
      end

      # Bridge between LibXML SAX and Moxml SAX
      #
      # Translates LibXML::XML::SaxParser events to Moxml::SAX::Handler events
      #
      # @private
      class LibXMLSAXBridge
        include ::LibXML::XML::SaxParser::Callbacks
        include Moxml::SAX::NamespaceSplitter

        def initialize(handler)
          @handler = handler
        end

        # Map LibXML events to Moxml events

        def on_start_document
          @handler.on_start_document
        end

        def on_end_document
          @handler.on_end_document
        end

        # libxml strips prefixes and namespace declarations from the
        # plain on_start_element callback; the _ns variants carry
        # them. The namespaces hash uses nil for the default
        # declaration — the same key convention as every other
        # bridge's split. Attribute name prefixes are lost by the
        # binding in both callbacks (documented limitation).
        def on_start_element_ns(name, attributes, prefix, _uri, namespaces)
          normalized = (attributes || {}).map { |k, v| [k.to_s, v] }
          attr_hash, = split_attributes_and_namespaces(normalized) do |v|
            Moxml::Adapter::Base.decode_entities(v)
          end
          qualified = prefix ? "#{prefix}:#{name}" : name.to_s
          @handler.on_start_element(qualified, attr_hash, namespaces || {})
        end

        def on_end_element_ns(name, prefix, _uri)
          qualified = prefix ? "#{prefix}:#{name}" : name.to_s
          @handler.on_end_element(qualified)
        end

        def on_characters(chars)
          @handler.on_characters(chars)
        end

        def on_cdata_block(content)
          @handler.on_cdata(content)
        end

        def on_comment(msg)
          @handler.on_comment(msg)
        end

        def on_processing_instruction(target, data)
          @handler.on_processing_instruction(target, data || "")
        end

        def on_error(msg)
          @handler.on_error(Moxml::ParseError.new(msg))
        end
      end
    end
  end
end
