# frozen_string_literal: true

require_relative "base"
require "libxml"
require_relative "customized_libxml"

module Moxml
  module Adapter
    class Libxml < Base
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
          output = "<!DOCTYPE #{@name}"
          if @external_id && !@external_id.empty?
            output << " PUBLIC \"#{@external_id}\""
            output << " \"#{@system_id}\"" if @system_id
          elsif @system_id && !@system_id.empty?
            output << " SYSTEM \"#{@system_id}\""
          end
          output << ">"
          output
        end
      end

      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          doc.root = element
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
          doctype_match = xml_string.match(/<!DOCTYPE\s+(\S+)(?:\s+PUBLIC\s+"([^"]+)"\s+"([^"]+)"|  \s+SYSTEM\s+"([^"]+)")?\s*>/i)

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
          DocumentBuilder.new(ctx).build(native_doc)
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

          # Handle wrapper classes
          return :element if node.is_a?(CustomizedLibxml::Element)
          return :text if node.is_a?(CustomizedLibxml::Text)
          return :cdata if node.is_a?(CustomizedLibxml::Cdata)
          return :comment if node.is_a?(CustomizedLibxml::Comment)
          if node.is_a?(CustomizedLibxml::ProcessingInstruction)
            return :processing_instruction
          end
          return :entity_reference if node.is_a?(CustomizedLibxml::EntityReference)
          return :doctype if node.is_a?(DoctypeWrapper)

          # Unwrap if needed
          native_node = unpatch_node(node)

          case native_node.node_type
          when ::LibXML::XML::Node::DOCUMENT_NODE
            :document
          when ::LibXML::XML::Node::ELEMENT_NODE
            :element
          when ::LibXML::XML::Node::TEXT_NODE
            :text
          when ::LibXML::XML::Node::CDATA_SECTION_NODE
            :cdata
          when ::LibXML::XML::Node::COMMENT_NODE
            :comment
          when ::LibXML::XML::Node::ATTRIBUTE_NODE
            :attribute
          when ::LibXML::XML::Node::PI_NODE
            :processing_instruction
          when ::LibXML::XML::Node::DTD_NODE
            :doctype
          else
            :unknown
          end
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
              # Skip whitespace-only text nodes
              next if child.text? && child.content.to_s.strip.empty?

              result << patch_node(child)
            end
          end

          # Include any EntityReference wrappers stored on the document
          doc = native_node.doc
          entity_refs = doc ? lookup_entity_refs(doc, native_node) : nil
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
            break unless current.text? && current.content.to_s.strip.empty?

            current = current.next
          end
          current ? patch_node(current) : nil
        end

        def previous_sibling(node)
          native_node = unpatch_node(node)
          current = native_node&.prev
          while current
            # Skip whitespace-only text nodes
            break unless current.text? && current.content.to_s.strip.empty?

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
            # Regular attribute without namespace
            native_elem[name_str] = value_str
            native_elem.attributes.get_attribute(name_str)
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

          # Try to get the attribute with the given name (handles namespaced attrs)
          value = native_elem[name.to_s]
          return value if value

          # If name contains ':', try to get as namespaced attribute
          if name.to_s.include?(":")
            prefix, local_name = name.to_s.split(":", 2)
            # Try to find attribute by namespace
            if native_elem.attributes?
              native_elem.each_attr do |attr|
                if attr.name == local_name || attr.name == name.to_s
                  # Check if attribute's namespace matches the prefix
                  if attr.ns && attr.ns.prefix == prefix
                    return attr.value
                  elsif attr.name == name.to_s
                    # Fallback: attribute name includes the prefix
                    return attr.value
                  end
                end
              end
            end
          end

          nil
        end

        def remove_attribute(element, name)
          native_elem = unpatch_node(element)
          return unless native_elem
          return unless native_elem.attributes?

          attr = native_elem.attributes.get_attribute(name.to_s)
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
          # Store on the document (stable identity) keyed by element.
          # LibXML creates new Ruby wrappers on each access, so element
          # object_id is unstable — we look up via == comparison.
          if child.is_a?(CustomizedLibxml::EntityReference)
            doc = native_elem.is_a?(::LibXML::XML::Document) ? native_elem : native_elem.doc
            store_entity_ref_on_doc(doc, native_elem, child)
            append_child_sequence_on_doc(doc, native_elem, :eref)
            return
          end

          # For LibXML: if parent has a DEFAULT namespace (nil/empty prefix) and child is an element without a namespace,
          # explicitly set the child's namespace to match the parent's for XPath compatibility
          # NOTE: Prefixed namespaces are NOT inherited, only default namespaces
          if native_elem.is_a?(::LibXML::XML::Node) && native_elem.namespaces&.namespace &&
              native_child.is_a?(::LibXML::XML::Node) && native_child.element? &&
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
              attachments.set(native_elem, :_pending_root_refresh, native_child.object_id)
            elsif native_elem.root
              # Document has root, add to it instead
              import_and_add(native_elem.doc, native_elem.root, native_child)
            end
          else
            import_and_add(native_elem.doc, native_elem, native_child)
            doc = native_elem.doc || native_elem
            append_child_sequence_on_doc(doc, native_elem, :native)
          end
        end

        # Store entity ref on the document (stable identity).
        # LibXML element wrappers are ephemeral, so we use == to find matching elements.
        def store_entity_ref_on_doc(doc, element, ref)
          pairs = attachments.get(doc, :_entity_ref_pairs) || []
          pair = pairs.find { |elem, _| elem == element }
          if pair
            pair[1] << ref
          else
            pairs << [element, [ref]]
          end
          attachments.set(doc, :_entity_ref_pairs, pairs)
        end

        # Look up entity refs for an element from the document
        def lookup_entity_refs(doc, element)
          pairs = attachments.get(doc, :_entity_ref_pairs)
          return nil unless pairs
          pair = pairs.find { |elem, _| elem == element }
          pair&.last
        end

        # Track child order on the document (stable identity)
        def append_child_sequence_on_doc(doc, element, type)
          pairs = attachments.get(doc, :_child_seq_pairs) || []
          pair = pairs.find { |elem, _| elem == element }
          if pair
            pair[1] << type
          else
            pairs << [element, [type]]
          end
          attachments.set(doc, :_child_seq_pairs, pairs)
        end

        # Look up child sequence for an element from the document
        def lookup_child_sequence(doc, element)
          pairs = attachments.get(doc, :_child_seq_pairs)
          return nil unless pairs
          pair = pairs.find { |elem, _| elem == element }
          pair&.last
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
          native_node.content = content.to_s if native_node
        end

        def cdata_content(node)
          native_node = unpatch_node(node)
          content = native_node&.content
          # LibXML may HTML-escape CDATA content, un-escape it
          return nil unless content

          content.gsub("&quot;", '"')
            .gsub("&apos;", "'")
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&amp;", "&")
        end

        def set_cdata_content(node, content)
          native_node = unpatch_node(node)
          # CDATA content should NOT be escaped
          native_node.content = content.to_s if native_node
        end

        def comment_content(node)
          native_node = unpatch_node(node)
          native_node&.content
        end

        def set_comment_content(node, content)
          native_node = unpatch_node(node)
          native_node.content = content.to_s if native_node
        end

        def processing_instruction_target(node)
          native_node = unpatch_node(node)
          native_node&.name
        end

        def processing_instruction_content(node)
          native_node = unpatch_node(node)
          content = native_node&.content
          # LibXML may HTML-escape the content, un-escape it
          return nil unless content

          content.gsub("&quot;", '"')
            .gsub("&apos;", "'")
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&amp;", "&")
        end

        def set_processing_instruction_content(node, content)
          native_node = unpatch_node(node)
          # Store raw content - LibXML will escape it
          native_node.content = content.to_s if native_node
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
          return unless native_elem && ns

          native_elem.namespaces.namespace = ns
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

          native_node.namespaces.definitions.map do |ns|
            ns
          end
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

          results = if ns_context.empty?
                      native_node.find(expression).to_a
                    else
                      native_node.find(expression, ns_context).to_a
                    end

          # Wrap results
          results.map { |n| patch_node(n) }
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
              # Use our custom serializer to control namespace output
              root_output = serialize_element_with_namespaces(
                native_node.root,
                true,
              )

              # Apply indentation if requested
              if options[:indent]&.positive?
                # First add newlines between elements
                formatted = add_newlines_to_xml(root_output)
                output << "\n" << indent_xml(formatted, options[:indent])
              else
                output << "\n" << root_output unless output.empty?
                output << root_output if output.empty?
              end
            end

            output
          else
            serialize_element_with_namespaces(native_node, true)
          end
        end

        def add_newlines_to_xml(xml_string)
          # Add newlines between XML elements for proper indentation
          # But don't add newlines between opening and immediate closing tags (e.g., <tag></tag>)
          # And most importantly, don't add newlines inside CDATA sections

          # First, protect CDATA sections by replacing them with placeholders
          # Manual scanning guarantees O(n) complexity with no backtracking (ReDoS-safe)
          cdata_sections = []
          result = +""
          pos = 0

          loop do
            # Find next CDATA start
            cdata_start = xml_string.index("<![CDATA[", pos)

            if cdata_start
              # Copy everything before CDATA
              result << xml_string[pos...cdata_start]

              # Find CDATA end
              cdata_content_start = cdata_start + 9 # Length of "<![CDATA["
              cdata_end = xml_string.index("]]>", cdata_content_start)

              if cdata_end
                # Extract full CDATA including markers
                full_cdata_end = cdata_end + 3 # Include "]]>"
                cdata_section = xml_string[cdata_start...full_cdata_end]

                # Store and add placeholder
                cdata_sections << cdata_section
                result << "__CDATA_PLACEHOLDER_#{cdata_sections.length - 1}__"

                # Continue after this CDATA
                pos = full_cdata_end
              else
                # Malformed CDATA (no closing "]]>") - copy as-is
                result << xml_string[cdata_start..]
                break
              end
            else
              # No more CDATA sections - copy rest
              result << xml_string[pos..]
              break
            end
          end

          protected = result

          # Add newlines between elements (but not in CDATA - already protected)
          with_newlines = protected.gsub(%r{(<[^>]+)>(?=<(?!/))}, "\\1>\n")

          # Restore CDATA sections
          cdata_sections.each_with_index do |cdata, index|
            with_newlines.sub!("__CDATA_PLACEHOLDER_#{index}__", cdata)
          end

          with_newlines
        end

        def indent_xml(xml_string, indent_size)
          # Simple line-by-line indentation
          lines = []
          level = 0

          xml_string.each_line do |line|
            line = line.strip
            next if line.empty?

            # Decrease level for closing tags
            level -= 1 if line.start_with?("</")
            level = [level, 0].max

            # Add indented line
            lines << ((" " * (indent_size * level)) + line)

            # Increase level for opening tags (but not self-closing or special tags)
            next unless line.start_with?("<") && !line.start_with?("</") &&
              !line.end_with?("/>") && !line.start_with?("<?") &&
              !line.start_with?("<!") && !line.include?("</")

            level += 1
          end

          lines.join("\n")
        end

        def duplicate_node(node)
          return nil unless node

          # Unwrap if wrapped
          native_node = unpatch_node(node)

          # LibXML is strict about document ownership
          # Create brand new NATIVE nodes that are document-independent
          # Wrappers are only used via patch_node when reading children
          case node_type(node)
          when :doctype
            # DoctypeWrapper - create a new one with same properties
            if node.is_a?(DoctypeWrapper)
              DoctypeWrapper.new(
                create_document,
                node.name,
                node.external_id,
                node.system_id,
              )
            else
              # Should not happen, but handle gracefully
              node
            end
          when :element
            new_node = ::LibXML::XML::Node.new(native_node.name)
            # new_node.line = node.line

            # Copy and set namespace definitions FIRST
            if native_node.is_a?(::LibXML::XML::Node)
              # First, copy all namespace definitions
              native_node.namespaces.each do |ns|
                ::LibXML::XML::Namespace.new(
                  new_node,
                  ns.prefix,
                  ns.href,
                )
              end

              # Then, set this element's own namespace if it has one
              if native_node.namespaces.namespace
                orig_ns = native_node.namespaces.namespace
                # Find the matching namespace we just created
                new_node.namespaces.each do |ns|
                  if ns.prefix == orig_ns.prefix && ns.href == orig_ns.href
                    new_node.namespaces.namespace = ns
                    break
                  end
                end
              end
            end

            # Copy attributes AFTER namespaces are set up
            # LibXML handles namespaced attributes through their full names
            if native_node.attributes?
              native_node.each_attr do |attr|
                # Get the full attribute name (may include namespace prefix)
                attr_name = if attr.ns&.prefix
                              "#{attr.ns.prefix}:#{attr.name}"
                            else
                              attr.name
                            end
                new_node[attr_name] = attr.value
              end
            end

            # Recursively copy children
            if native_node.children?
              native_node.each_child do |child|
                # Skip whitespace-only text nodes
                next if child.text? && child.content.to_s.strip.empty?

                # Recursively duplicate the child
                child_copy = duplicate_node(child)
                new_node << child_copy
              end
            end

            new_node
          when :text
            ::LibXML::XML::Node.new_text(native_node.content)
          when :cdata
            ::LibXML::XML::Node.new_cdata(native_node.content)
          when :comment
            ::LibXML::XML::Node.new_comment(native_node.content)
          when :processing_instruction
            ::LibXML::XML::Node.new_pi(native_node.name, native_node.content)
          else
            # For other types, try dup as fallback
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

        def prepare_for_new_document(node, target_doc)
          return node unless node && target_doc

          # For LibXML, we need to duplicate ALL nodes to avoid
          # document ownership issues. Simply importing doesn't work
          # because nodes from the parsed document still have references.
          duplicate_node(node)
        end

        def has_declaration?(native_doc, wrapper)
          decl = attachments.get(native_doc, :declaration)
          if decl
            !decl.removed
          else
            wrapper.has_xml_declaration
          end
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
                          " xmlns=\"#{escape_xml(uri)}\""
                        else
                          " xmlns:#{prefix}=\"#{escape_xml(uri)}\""
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
              output << " #{attr_name}=\"#{escape_xml(attr.value)}\""
            end
          end

          # Always use verbose format <tag></tag> for consistency with other adapters
          output << ">"
          if elem.children?
            elem.each_child do |child|
              # Skip whitespace-only text nodes
              next if child.text? && child.content.to_s.strip.empty?

              output << serialize_node(child)
            end
          end

          # Append any EntityReference wrappers stored on the document
          doc = elem.doc
          entity_refs = doc ? lookup_entity_refs(doc, elem) : nil
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
            escape_text(node.content)
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

        def escape_text(text)
          text.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
        end

        def escape_xml(text)
          text.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub("\"", "&quot;")
        end

        def escape_attribute_value(value)
          escaped = value.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub("\"", "&quot;")
          escaped.to_s
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
              copied = duplicate_node(child)
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

        def serialize_element_with_namespaces(elem, include_ns = true)
          output = "<#{elem.name}"

          # Include namespace definitions:
          # - On root element (include_ns = true), output ALL namespace definitions
          # - On child elements, output namespace definitions that override parent namespaces
          if elem.is_a?(::LibXML::XML::Node) && elem.namespaces.respond_to?(:definitions)
            # Get parent's namespace definitions to detect overrides
            parent_ns_defs = if !include_ns && elem.parent && !elem.parent.is_a?(::LibXML::XML::Document)
                               parent_namespaces = {}
                               if elem.parent.is_a?(::LibXML::XML::Node)
                                 elem.parent.namespaces.each do |ns|
                                   parent_namespaces[ns.prefix] = ns.href
                                 end
                               end
                               parent_namespaces
                             else
                               {}
                             end

            seen_ns = {}
            elem.namespaces.definitions.each do |ns|
              prefix = ns.prefix
              uri = ns.href
              next if seen_ns.key?(prefix)

              # Output namespace if:
              # 1. This is root element (include_ns = true), OR
              # 2. This namespace overrides a parent namespace (different URI for same prefix)
              should_output = include_ns ||
                (parent_ns_defs.key?(prefix) && parent_ns_defs[prefix] != uri)

              next unless should_output

              seen_ns[prefix] = true
              output << if prefix.nil? || prefix.empty?
                          " xmlns=\"#{escape_xml(uri)}\""
                        else
                          " xmlns:#{prefix}=\"#{escape_xml(uri)}\""
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
              output << " #{attr_name}=\"#{escape_xml(attr.value)}\""
            end
          end

          # Check for entity refs stored on the document
          # LibXML element wrappers are ephemeral, so look up via == comparison
          doc = elem.doc
          entity_refs = doc ? lookup_entity_refs(doc, elem) : nil
          child_sequence = doc ? lookup_child_sequence(doc, elem) : nil

          # Always use verbose format <tag></tag> for consistency with other adapters
          output << ">"

          if entity_refs && !entity_refs.empty? && child_sequence
            # Interleave native children with entity refs using tracked sequence
            native_children = []
            if elem.children?
              elem.each_child { |c| native_children << c unless c.text? && c.content.to_s.strip.empty? }
            end

            eref_idx = 0
            native_idx = 0
            child_sequence.each do |type|
              case type
              when :native
                if native_idx < native_children.size
                  child = native_children[native_idx]
                  native_idx += 1
                  wrapped_child = patch_node(child)
                  output << if wrapped_child.is_a?(CustomizedLibxml::Node) && !wrapped_child.is_a?(CustomizedLibxml::Element)
                              wrapped_child.to_xml
                            elsif child.element?
                              serialize_element_with_namespaces(child, false)
                            else
                              serialize_node(child)
                            end
                end
              when :eref
                if eref_idx < entity_refs.size
                  output << entity_refs[eref_idx].to_xml
                  eref_idx += 1
                end
              end
            end
          elsif elem.children?
            elem.each_child do |child|
              # Skip whitespace-only text nodes
              next if child.text? && child.content.to_s.strip.empty?

              # Wrap the child and serialize
              wrapped_child = patch_node(child)
              output << if wrapped_child.is_a?(CustomizedLibxml::Node) && !wrapped_child.is_a?(CustomizedLibxml::Element)
                          # Use wrapper's to_xml for proper serialization
                          wrapped_child.to_xml
                        elsif child.element?
                          # Recursively serialize child elements
                          serialize_element_with_namespaces(child, false)
                        else
                          serialize_node(child)
                        end
            end
          end
          output << "</#{elem.name}>"

          output
        end

        def remove_indentation(xml_string)
          # Remove all newlines and extra spaces between tags
          xml_string.gsub(/>\s+</, "><").gsub(/\n\s*/, "")
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
          if node.is_a?(::LibXML::XML::Node) && node.namespaces.respond_to?(:namespace)
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
      end

      # Bridge between LibXML SAX and Moxml SAX
      #
      # Translates LibXML::XML::SaxParser events to Moxml::SAX::Handler events
      #
      # @private
      class LibXMLSAXBridge
        include ::LibXML::XML::SaxParser::Callbacks

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

        def on_start_element(name, attributes)
          # Convert LibXML attributes hash to separate attrs and namespaces
          attr_hash = {}
          ns_hash = {}

          attributes&.each do |attr_name, attr_value|
            if attr_name.to_s.start_with?("xmlns")
              # Namespace declaration
              prefix = if attr_name.to_s == "xmlns"
                         nil
                       else
                         attr_name.to_s.sub(
                           "xmlns:", ""
                         )
                       end
              ns_hash[prefix] = attr_value
            else
              attr_hash[attr_name.to_s] = attr_value
            end
          end

          @handler.on_start_element(name.to_s, attr_hash, ns_hash)
        end

        def on_end_element(name)
          @handler.on_end_element(name.to_s)
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
