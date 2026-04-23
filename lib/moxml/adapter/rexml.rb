# frozen_string_literal: true

require_relative "base"
require "rexml/document"
require "rexml/xpath"
require "set"
require_relative "customized_rexml"

module Moxml
  module Adapter
    class Rexml < Base
      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def parse(xml, options = {}, _context = nil)
          xml = "" if xml.nil?

          # Handle frozen strings by creating a mutable copy
          processed_xml = if xml.frozen?
                            xml.dup.force_encoding("UTF-8").encode("UTF-8")
                          else
                            xml.force_encoding("UTF-8").encode("UTF-8")
                          end

          # Preprocess entities to avoid double-escaping on output
          processed_xml = preprocess_entities(processed_xml)

          native_doc = begin
            ::REXML::Document.new(processed_xml)
          rescue ::REXML::ParseException => e
            if options[:strict]
              raise Moxml::ParseError.new(
                e.message,
                line: e.line,
                source: xml.is_a?(String) ? xml[0..100] : nil,
              )
            end
            create_document
          end

          ctx = _context || Context.new(:rexml)
          DocumentBuilder.new(ctx).build(native_doc)
        end

        def extract_encoding_from_xml(xml)
          # Match XML declaration pattern: <?xml version="..." encoding="..."?>
          # Use atomic group (?>) to prevent polynomial backtracking ReDoS
          match = xml.match(/<\?xml(?>[^>]*)\bencoding\s*=\s*["']([^"']+)["']/i)
          match ? match[1] : "UTF-8"
        end

        # SAX parsing implementation for REXML
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          require "rexml/parsers/sax2parser"
          require "rexml/source"
          require "stringio"

          bridge = REXMLSAX2Bridge.new(handler)

          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s
          source = ::REXML::IOSource.new(StringIO.new(xml_string))

          parser = ::REXML::Parsers::SAX2Parser.new(source)
          parser.listen(bridge)
          parser.parse
        rescue ::REXML::ParseException => e
          error = Moxml::ParseError.new(e.message, line: e.line)
          handler.on_error(error)
        end

        def create_document(_native_doc = nil)
          ::REXML::Document.new
        end

        def create_native_element(name, _owner_doc = nil)
          ::REXML::Element.new(name.to_s)
        end

        def create_native_text(content, _owner_doc = nil)
          ::REXML::Text.new(content.to_s, true, nil)
        end

        def create_native_entity_reference(name)
          ::Moxml::Adapter::CustomizedRexml::EntityReference.new(name)
        end

        def entity_reference_name(node)
          node.name if node.is_a?(::Moxml::Adapter::CustomizedRexml::EntityReference)
        end

        def create_native_cdata(content, _owner_doc = nil)
          ::REXML::CData.new(content.to_s)
        end

        def create_native_comment(content, _owner_doc = nil)
          ::REXML::Comment.new(content.to_s)
        end

        def create_native_processing_instruction(target, content)
          # Clone strings to avoid frozen string errors
          ::REXML::Instruction.new(target.to_s.dup, content.to_s.dup)
        end

        def create_native_declaration(version, encoding, standalone)
          ::REXML::XMLDecl.new(version, encoding&.downcase, standalone)
        end

        def create_native_doctype(name, external_id, system_id)
          return nil unless name

          parts = [name]
          if external_id
            parts.push("PUBLIC", %("#{external_id}"))
            parts << %("#{system_id}") if system_id
          elsif system_id
            parts.push("SYSTEM", %("#{system_id}"))
          end

          ::REXML::DocType.new(parts.join(" "))
        end

        def set_root(doc, element)
          doc.add_element(element)
        end

        def node_type(node)
          case node
          when ::REXML::Document then :document
          when ::REXML::Element then :element
          when ::REXML::CData then :cdata
          when ::REXML::Text then :text
          when ::REXML::Comment then :comment
          when ::REXML::Attribute then :attribute # but in fact it may be a namespace as well
          when ::REXML::Namespace then :namespace # we don't use this one
          when ::REXML::Instruction then :processing_instruction
          when ::REXML::DocType then :doctype
          when ::REXML::XMLDecl then :declaration
          when ::Moxml::Adapter::CustomizedRexml::EntityReference then :entity_reference
          else :unknown
          end
        end

        def set_node_name(node, name)
          case node
          when ::REXML::Element
            node.name = name.to_s
          when ::REXML::Instruction
            node.target = name.to_s
          end
        end

        def node_name(node)
          case node
          when ::REXML::Element, ::REXML::DocType
            node.name
          when ::REXML::XMLDecl
            "xml"
          when ::REXML::Instruction
            node.target
          end
        end

        def duplicate_node(node)
          if node.respond_to?(:deep_clone)
            node.deep_clone
          else
            Marshal.load(Marshal.dump(node))
          end
        end

        def children(node)
          return [] unless node.is_a?(::REXML::Parent)

          # Get all children and filter out empty text nodes between elements
          result = node.children.reject do |child|
            child.is_a?(::REXML::Text) &&
              child.to_s.strip.empty? &&
              !(child.next_sibling.nil? && child.previous_sibling.nil?)
          end

          # Include any EntityReference wrappers stored alongside native children
          entity_refs = attachments.get(node, :entity_refs)
          result.concat(entity_refs) if entity_refs

          # Ensure uniqueness by object_id to prevent duplicates
          result.uniq(&:object_id)
        end

        def parent(node)
          node.parent
        end

        def next_sibling(node)
          current = node.next_sibling

          # Skip empty text nodes and duplicates
          seen = Set.new
          while current
            if current.is_a?(::REXML::Text) && current.to_s.strip.empty?
              current = current.next_sibling
              next
            end

            # Check for duplicates
            if seen.include?(current.object_id)
              current = current.next_sibling
              next
            end

            seen.add(current.object_id)
            break
          end

          current
        end

        def previous_sibling(node)
          current = node.previous_sibling

          # Skip empty text nodes and duplicates
          seen = Set.new
          while current
            if current.is_a?(::REXML::Text) && current.to_s.strip.empty?
              current = current.previous_sibling
              next
            end

            # Check for duplicates
            if seen.include?(current.object_id)
              current = current.previous_sibling
              next
            end

            seen.add(current.object_id)
            break
          end

          current
        end

        def document(node)
          node.document
        end

        def root(document)
          document.root
        end

        def attributes(element)
          return [] unless element.is_a?(::REXML::Element)

          # Only return non-namespace attributes
          element.attributes.values
            .reject { |attr| attr.prefix.to_s.start_with?("xmlns") }
        end

        def attribute_element(attribute)
          attribute.element
        end

        def set_attribute(element, name, value)
          element.attributes[name&.to_s] = value&.to_s
          element.attributes.get_attribute(name&.to_s)
        end

        def set_attribute_name(attribute, name)
          old_name = attribute.expanded_name
          attribute.name = name
          # Rexml doesn't change the keys of the attributes hash
          element = attribute.element
          element.attributes.delete(old_name)
          element.attributes << attribute
        end

        def set_attribute_value(attribute, value)
          attribute.normalized = value
        end

        def get_attribute(element, name)
          element.attributes.get_attribute(name)
        end

        def get_attribute_value(element, name)
          element.attributes[name]
        end

        def remove_attribute(element, name)
          element.delete_attribute(name.to_s)
        end

        def add_child(element, child)
          # Special handling for declarations on REXML documents
          if element.is_a?(::REXML::Document) && child.is_a?(::REXML::XMLDecl)
            # Track declaration state in attachment map
            attachments.set(element, :xml_declaration, child)
          end

          case child
          when String
            element.add_text(child)
            append_child_sequence(element, :native)
          when ::Moxml::Adapter::CustomizedRexml::EntityReference
            # REXML doesn't support custom node types in its tree.
            # Store alongside native children via attachment map.
            refs = attachments.get(element, :entity_refs) || []
            refs << child
            attachments.set(element, :entity_refs, refs)
            append_child_sequence(element, :eref)
          else
            element.add(child)
            append_child_sequence(element, :native)
          end
        end

        def append_child_sequence(element, type)
          seq = attachments.get(element, :child_sequence) || []
          seq << type
          attachments.set(element, :child_sequence, seq)
        end

        def add_previous_sibling(node, sibling)
          parent = node.parent
          # caveat: Rexml fails if children belong to the same parent and are already in a correct order
          # example: "<root><a/><b/></root>"
          # add_previous_sibling(node_b, node_a)
          # result: "<root><b/><a/></root>"
          # expected result: "<root><a/><b/></root>"
          parent.insert_before(node, sibling)
        end

        def add_next_sibling(node, sibling)
          parent = node.parent
          parent.insert_after(node, sibling)
        end

        def remove(node)
          # Special handling for declarations on REXML documents
          if node.is_a?(::REXML::XMLDecl) && node.parent.is_a?(::REXML::Document)
            # Clear declaration state in attachment map
            attachments.set(node.parent, :xml_declaration, nil)
          end

          node.remove
        end

        def replace(node, new_node)
          node.replace_with(new_node)
        end

        def replace_children(element, children)
          element.children.each(&:remove)
          children.each { |child| element.add(child) }
        end

        def declaration_attribute(node, name)
          case name
          when "version"
            node.version
          when "encoding"
            node.encoding
          when "standalone"
            node.standalone
          end
        end

        def set_declaration_attribute(node, name, value)
          case name
          when "version"
            node.version = value
          when "encoding"
            node.encoding = value
          when "standalone"
            node.standalone = value
          end
        end

        def comment_content(node)
          node.string
        end

        def set_comment_content(node, content)
          node.string = content.to_s
        end

        def cdata_content(node)
          node.value
        end

        def set_cdata_content(node, content)
          node.value = content.to_s
        end

        def processing_instruction_target(node)
          node.target
        end

        def processing_instruction_content(node)
          node.content
        end

        def set_processing_instruction_content(node, content)
          node.content = content.to_s
        end

        def text_content(node)
          case node
          when ::REXML::Text, ::REXML::CData
            node.value.to_s
          when ::Moxml::Adapter::CustomizedRexml::EntityReference
            ""
          when ::REXML::Element
            # Extract text recursively from all children to match other adapters
            extract_text_recursively(node)
          end.to_s
        end

        def extract_text_recursively(element)
          return "" unless element

          text = ""
          element.children.each do |child|
            case child
            when ::REXML::Text
              # Preserve original spacing from text nodes exactly including newlines and all whitespace
              text += child.value
            when ::REXML::Element
              # Extract text recursively from child element
              child_text = extract_text_recursively(child)
              # Concatenate directly like other adapters - NO SPACE INSERTION
              text += child_text
            end
          end
          # Don't strip - preserve original spacing including newlines
          text
        end

        def inner_text(node)
          # Get direct text children only, filter duplicates
          text_children = node.children
            .grep(::REXML::Text)
            .uniq(&:object_id)
          text_children.map(&:value).join
        end

        def set_text_content(node, content)
          case node
          when ::REXML::Text, ::REXML::CData
            node.value = content.to_s
          when ::REXML::Element
            # Remove existing text nodes to prevent duplicates
            node.texts.each(&:remove)
            # Add new text content
            node.add_text(content.to_s)
          end
        end

        # add a namespace definition, keep the element name unchanged
        def create_native_namespace(element, prefix, uri)
          element.add_namespace(prefix.to_s, uri)
          ::REXML::Attribute.new(prefix.to_s, uri, element)
        end

        # add a namespace prefix to the element name AND a namespace definition
        def set_namespace(element, ns)
          prefix = ns.name.to_s.empty? ? "xmlns" : ns.name.to_s
          if element.is_a?(::REXML::Element)
            element.add_namespace(prefix,
                                  ns.value)
          end
          element.name = "#{prefix}:#{element.name}"
          owner = element.is_a?(::REXML::Attribute) ? element.element : element
          ::REXML::Attribute.new(prefix, ns.value, owner)
        end

        def namespace_prefix(node)
          node.name unless node.name == "xmlns"
        end

        def namespace_uri(node)
          node.value
        end

        def namespace(node)
          prefix = node.prefix
          uri = node.namespace(prefix)
          return if prefix.to_s.empty? && uri.to_s.empty?

          owner = node.is_a?(::REXML::Attribute) ? node.element : node
          ::REXML::Attribute.new(prefix, uri, owner)
        end

        def namespace_definitions(node)
          return [] unless node.is_a?(::REXML::Element)

          result = []
          node.attributes.each_attribute do |attr|
            if attr.prefix == "xmlns"
              result << attr
            elsif attr.name == "xmlns" && attr.prefix.empty?
              result << attr
            end
          end
          result
        end

        def in_scope_namespaces(element)
          namespaces = {}
          element.namespaces.each do |prefix, uri|
            key = prefix.to_s.empty? ? "xmlns" : prefix.to_s
            ns = ::REXML::Attribute.new(key, uri, element)
            namespaces[prefix] = ns
          end
          namespaces.values
        end

        # Doctype accessor methods
        def doctype_name(native)
          native.name
        end

        def doctype_external_id(native)
          native.public
        end

        def doctype_system_id(native)
          native.system
        end

        # not used at the moment
        # but may be useful when the xpath is upgraded to work with namespaces
        def prepare_xpath_namespaces(node)
          ns = {}

          # Get all namespace definitions in scope
          all_ns = namespace_definitions(node)

          # Convert to XPath-friendly format
          all_ns.each do |prefix, uri|
            if prefix.to_s.empty?
              ns["xmlns"] = uri
            else
              ns[prefix] = uri
            end
          end

          ns
        end

        def xpath(node, expression, _namespaces = {})
          node.get_elements(expression).to_a
        rescue ::REXML::ParseException => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "REXML",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = {})
          results = xpath(node, expression, namespaces)
          results.first
        end

        def serialize(node, options = {})
          output = +""

          if node.is_a?(::REXML::Document)
            # Check if we should include declaration
            # Priority: explicit option > check if document has xml_decl
            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  else
                                    # Include declaration only if document has xml_decl
                                    !node.xml_decl.nil?
                                  end

            # Include XML declaration only if should_include_decl and xml_decl exists
            if should_include_decl && node.xml_decl
              decl = node.xml_decl
              decl.encoding = options[:encoding] if options[:encoding]
              output << "<?xml"
              output << %( version="#{decl.version}") if decl.version
              output << %( encoding="#{decl.encoding}") if decl.encoding
              output << %( standalone="#{decl.standalone}") if decl.standalone
              output << "?>"
            end

            # output << "\n"
            node.doctype&.write(output)

            # Write processing instructions
            node.children.each do |child|
              next unless [::REXML::Instruction, ::REXML::CData,
                           ::REXML::Comment, ::REXML::Text].include?(child.class)

              write_with_formatter(child, output, options[:indent] || 2)
              # output << "\n"
            end

            if node.root
              write_with_formatter(node.root, output,
                                   options[:indent] || 2)
            end
          else
            write_with_formatter(node, output, options[:indent] || 2)
          end

          output.strip
        end

        def has_declaration?(native_doc, wrapper)
          xml_decl = attachments.get(native_doc, :xml_declaration)
          if xml_decl.nil?
            # Attachment key doesn't exist - check native doc or wrapper flag
            if attachments.key?(native_doc, :xml_declaration)
              # Explicitly set to nil (was removed)
              false
            else
              wrapper.has_xml_declaration
            end
          else
            true
          end
        end

        private

        def write_with_formatter(node, output, indent = 2)
          formatter = ::Moxml::Adapter::CustomizedRexml::Formatter.new(
            indentation: indent, self_close_empty: false, adapter: self,
          )
          formatter.write(node, output)
        end
      end
    end

    # Bridge between REXML SAX2 and Moxml SAX
    #
    # Translates REXML::SAX2Parser events to Moxml::SAX::Handler events
    #
    # @private
    class REXMLSAX2Bridge
      def initialize(handler)
        @handler = handler
      end

      # REXML splits element name into uri/localname/qname
      def start_element(_uri, _localname, qname, attributes)
        # Convert REXML attributes to hash
        attr_hash = {}
        ns_hash = {}

        attributes.each do |name, value|
          if name.to_s.start_with?("xmlns")
            # Namespace declaration
            prefix = name.to_s == "xmlns" ? nil : name.to_s.sub("xmlns:", "")
            ns_hash[prefix] = value
          else
            attr_hash[name.to_s] = value
          end
        end

        # Use qname (qualified name) for element name
        @handler.on_start_element(qname, attr_hash, ns_hash)
      end

      def end_element(_uri, _localname, qname)
        @handler.on_end_element(qname)
      end

      def characters(text)
        @handler.on_characters(text)
      end

      def cdata(content)
        @handler.on_cdata(content)
      end

      def comment(text)
        @handler.on_comment(text)
      end

      def processing_instruction(target, data)
        @handler.on_processing_instruction(target, data || "")
      end

      def start_document
        @handler.on_start_document
      end

      def end_document
        @handler.on_end_document
      end

      # REXML calls these but we don't need to handle them
      def xmldecl(version, encoding, standalone)
        # XML declaration - we don't need to do anything
      end

      def progress(position)
        # Progress callback - we don't need to do anything
      end
    end
  end
end
