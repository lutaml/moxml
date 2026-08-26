# frozen_string_literal: true

return if RUBY_ENGINE == "opal"

require "libxml"

module Moxml
  module Adapter
    class Libxml < Base
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
        def moxml_wrappers_recursable
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

          # Extract DOCTYPE before parsing
          doctype_match = xml_string.match(/<!DOCTYPE\s+([^\s>]+)(?:\s+PUBLIC\s+"([^"]+)"\s+"([^"]+)"|\s+SYSTEM\s+"([^"]+)")?\s*>/i)

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

          # Handle Document specially - it doesn't have children? method
          if native_node.is_a?(::LibXML::XML::Document)
            result = []

            # Include DOCTYPE if present
            doctype_wrapper = attachments.get(native_node, :doctype)
            result << doctype_wrapper if doctype_wrapper

            return result unless native_node.root

            result << patch_node(native_node.root)
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
                  true,
                  indent_size,
                  0,
                  eref_active: eref_active,
              )

              output << "\n" << root_output unless output.empty?
              output << root_output if output.empty?
            end

            output
          else
            serialize_element_with_namespaces(native_node, true)
          end
        end

        # Possessive-quantifier form: no backtracking, so pathological
        # attribute content cannot blow up the expansion pass.
        EMPTY_ELEMENT_EXPANSION_RE = %r{
          <([A-Za-z_][\w.:-]*+)
          ((?:"[^"]*+"|'[^']*+'|[^<>"'/]++)*+)
          />
        }x
        private_constant :EMPTY_ELEMENT_EXPANSION_RE

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

        def serialize_element_with_namespaces(elem, include_ns = true,
                                               indent_size = 0, depth = 0,
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

        def doc_eref_active?(doc)
          entity_ref_registry(doc).active?
        end

        def entity_ref_registry(doc)
          EntityRefRegistry.new(attachments, doc)
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

        # Regex used in place of `content.to_s.strip.empty?` for whitespace-only
        # text detection — `match?` allocates nothing while `.strip` makes a
        # throwaway copy of every text node's content on each visit.
        NON_WHITESPACE_RE = /\S/
        private_constant :NON_WHITESPACE_RE

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
            return serialize_element_with_namespaces(child, false, indent_size, depth + 1,
                                                     eref_active: eref_active)
          end

          wrapped_child = patch_node(child)
          if wrapped_child.is_a?(CustomizedLibxml::Node)
            wrapped_child.to_xml
          else
            serialize_node(child)
          end
        end

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
