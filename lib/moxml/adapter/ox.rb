# frozen_string_literal: true

require_relative "base"
require "ox"
require "stringio"
require_relative "customized_ox"

# insert :parent methods to all Ox classes inherit the Node class
Ox::Node.attr_accessor :parent
module Moxml
  module Adapter
    class Ox < Base
      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          replace_children(doc, [element])
        end

        def needs_entity_preprocessing?
          true
        end

        def parse(xml, options = {}, _context = nil)
          processed_xml = needs_entity_preprocessing? ? preprocess_entities(xml) : xml
          native_doc = begin
            result = ::Ox.parse(processed_xml)

            # result can be either Document or Element
            if result.is_a?(::Ox::Document)
              assign_parents(result)
              validate_single_root(result) if options[:strict]
              result
            else
              doc = ::Ox::Document.new
              doc << result
              assign_parents(doc)
              doc
            end
          rescue ::Ox::ParseError => e
            raise Moxml::ParseError.new(
              e.message,
              source: xml.is_a?(String) ? xml[0..100] : nil,
            )
          end

          ctx = _context || Context.new(:ox)
          Document.new(native_doc, ctx)
        end

        # SAX parsing implementation for Ox
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          # Create bridge that translates Ox SAX to Moxml SAX
          bridge = OxSAXBridge.new(handler)

          # Parse using Ox's SAX parser
          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s

          begin
            ::Ox.sax_parse(bridge, StringIO.new(xml_string))
            # Ox doesn't automatically call end_document, so we do it manually
            bridge.end_document
          rescue ::Ox::ParseError => e
            error = Moxml::ParseError.new(e.message)
            handler.on_error(error)
          end
        end

        def create_document(native_doc = nil)
          attrs = native_doc&.attributes || {}
          ::Ox::Document.new(**attrs)
        end

        def create_native_element(name, _owner_doc = nil)
          element = ::Ox::Element.new(name)
          element
        end

        def create_native_text(content, _owner_doc = nil)
          content
        end

        def create_native_entity_reference(name)
          ::Moxml::Adapter::CustomizedOx::EntityReference.new(name)
        end

        def entity_reference_name(node)
          node.name if node.is_a?(::Moxml::Adapter::CustomizedOx::EntityReference)
        end

        def create_native_cdata(content, _owner_doc = nil)
          ::Ox::CData.new(content)
        end

        def create_native_comment(content, _owner_doc = nil)
          ::Ox::Comment.new(content)
        end

        def create_native_doctype(name, external_id, system_id)
          ::Ox::DocType.new(
            "#{name} PUBLIC \"#{external_id}\" \"#{system_id}\"",
          )
        end

        def create_native_processing_instruction(target, content)
          inst = ::Ox::Instruct.new(target)
          set_processing_instruction_content(inst, content)
          inst
        end

        def create_native_declaration(version, encoding, standalone)
          inst = ::Ox::Instruct.new("xml")
          set_attribute(inst, "version", version)
          set_attribute(inst, "encoding", encoding)
          set_attribute(inst, "standalone", standalone)
          inst
        end

        def declaration_attribute(declaration, attr_name)
          get_attribute_value(declaration, attr_name)
        end

        def set_declaration_attribute(declaration, attr_name, value)
          set_attribute(declaration, attr_name, value)
        end

        def create_native_namespace(element, prefix, uri)
          ns = ::Moxml::Adapter::CustomizedOx::Namespace.new(prefix, uri,
                                                             element)
          set_attribute(element, ns.expanded_prefix, uri)
          ns
        end

        def set_namespace(element, ns)
          return unless element.is_a?(::Ox::Element) || element.is_a?(::Ox::Node)

          prefix = ns.prefix
          # attributes don't have attributes but can have a namespace prefix
          if element.is_a?(::Ox::Element)
            set_attribute(element, ns.expanded_prefix,
                          ns.uri)
          end
          element.name = [prefix,
                          element.name.delete_prefix("xmlns:")].compact.join(":")
          namespace(element)
        end

        def namespace(element)
          prefix =
            if element.is_a?(::Moxml::Adapter::CustomizedOx::Attribute)
              element.prefix
            elsif element.name.include?(":")
              element.name.split(":").first
            end
          attr_name = ["xmlns", prefix].compact.join(":")

          ([element] + ancestors(element)).each do |node|
            next unless node.is_a?(::Ox::Element) && node.attributes

            if node[attr_name]
              return ::Moxml::Adapter::CustomizedOx::Namespace.new(
                prefix, node[attr_name], element
              )
            end
          end

          nil
        end

        def ancestors(node)
          return [] unless (parent = parent(node))

          [parent] + ancestors(parent)
        end

        def processing_instruction_target(node)
          node.target
        end

        def node_type(node)
          case node
          when ::Ox::Document then :document
          when ::Moxml::Adapter::CustomizedOx::Text, String then :text
          when ::Ox::CData then :cdata
          when ::Ox::Comment then :comment
          when ::Ox::Instruct then :processing_instruction
          when ::Ox::Element then :element
          when ::Ox::DocType then :doctype
          when ::Moxml::Adapter::CustomizedOx::EntityReference then :entity_reference
          when ::Moxml::Adapter::CustomizedOx::Namespace then :banespace
          when ::Moxml::Adapter::CustomizedOx::Attribute then :attribute
          else :unknown
          end
        end

        def node_name(node)
          name = begin
            node.value
          rescue StandardError
            node.name
          end

          # Strip namespace prefix if present
          name.to_s.split(":", 2).last
        end

        def set_node_name(node, name)
          case node
          when ::Ox::Element then node.name = name
          when ::Ox::Instruct then node.value = name
          end
        end

        def duplicate_node(node)
          Marshal.load(Marshal.dump(node))
        end

        def patch_node(node, parent = nil)
          new_node =
            case node
            # it can be either attribute or namespace
            when Array then ::Moxml::Adapter::CustomizedOx::Attribute.new(
              node.first, node.last
            )
            when Hash then ::Moxml::Adapter::CustomizedOx::Attribute.new(
              node.keys.first, node.values.first
            )
            when String then ::Moxml::Adapter::CustomizedOx::Text.new(node)
            else node
            end

          new_node.parent = parent if new_node.is_a?(::Ox::Node)

          new_node
        end

        def unpatch_node(node)
          case node
          # it can be either attribute or namespace
          when ::Moxml::Adapter::CustomizedOx::Attribute then [node.name,
                                                               node.value]
          # when ::Moxml::Adapter::CustomizedOx::Attribute then { node.name => node.value }
          when ::Moxml::Adapter::CustomizedOx::Text then node.value
          when ::Moxml::Adapter::CustomizedOx::EntityReference then node
          else node
          end
        end

        def children(node)
          return [] unless node.is_a?(::Ox::Element) || node.is_a?(::Ox::Document)

          result = node.nodes || []
          # Ox doesn't set parent references during parsing.
          # Set them here so parent/sibling navigation works.
          result.each do |child|
            child.parent = node if child.respond_to?(:parent=)
          end
          result
        end

        def parent(node)
          node.parent if node.is_a?(::Ox::Node)
        end

        def next_sibling(node)
          return unless (parent = node.parent)

          siblings = parent.nodes
          idx = siblings.index(unpatch_node(node))
          idx ? patch_node(siblings[idx + 1], parent) : nil
        end

        def previous_sibling(node)
          return unless (parent = parent(node))

          siblings = parent.nodes
          idx = siblings.index(unpatch_node(node))
          idx&.positive? ? patch_node(siblings[idx - 1], parent) : nil
        end

        def document(node)
          current = node
          current = parent(current) while parent(current)
          current
        end

        def root(document)
          document.nodes&.find { |node| node.is_a?(::Ox::Element) }
        end

        def attributes(element)
          return [] unless element.is_a?(::Ox::Element) && element.attributes

          element.attributes.filter_map do |name, value|
            next if name.to_s.start_with?("xmlns")

            # Ensure value is passed correctly - Ox stores with symbol keys
            ::Moxml::Adapter::CustomizedOx::Attribute.new(
              name.to_s, value, element
            )
          end
        end

        def attribute_element(attribute)
          attribute.parent
        end

        def set_attribute(element, name, value)
          element.attributes ||= {}
          if value.nil?
            # Ox converts all values to strings
            remove_attribute(element, name)
          else
            element.attributes[name.to_s] = value
          end

          ::Moxml::Adapter::CustomizedOx::Attribute.new(
            name.to_s, value&.to_s, element
          )
        end

        def set_attribute_name(attribute, name)
          old_name = attribute.name
          attribute.name = name.to_s
          # Ox doesn't change the keys of the attributes hash
          element = attribute.parent
          element.attributes.delete(old_name)
          element.attributes[name] = attribute.value
        end

        def set_attribute_value(attribute, new_value)
          if new_value.nil?
            # Ox converts all values to strings
            remove_attribute(attribute.parent, attribute.name)
          else
            attribute.value = new_value
            attribute.parent.attributes[attribute.name] = new_value
          end
        end

        def get_attribute(element, name)
          return unless element.is_a?(::Ox::HasAttrs) && element.attributes
          unless element.attributes.key?(name.to_s) || element.attributes.key?(name.to_s.to_sym)
            return
          end

          # Ox stores attributes with symbol keys, so try both string and symbol
          value = element.attributes[name.to_s] || element.attributes[name.to_s.to_sym]

          ::Moxml::Adapter::CustomizedOx::Attribute.new(
            name.to_s, value, element
          )
        end

        def get_attribute_value(element, name)
          element[name]
        end

        def remove_attribute(element, name)
          return unless element.is_a?(::Ox::HasAttrs) && element.attributes

          element.attributes.delete(name.to_s)
          element.attributes.delete(name.to_s.to_sym)
        end

        def add_child(element, child)
          # Special handling for declarations on Ox documents
          if element.is_a?(::Ox::Document) && child.is_a?(::Ox::Instruct) && child.target == "xml"
            # Transfer declaration attributes to document
            element.attributes ||= {}
            if child.attributes["version"]
              element.attributes[:version] =
                child.attributes["version"]
            end
            if child.attributes["encoding"]
              element.attributes[:encoding] =
                child.attributes["encoding"]
            end
            if child.attributes["standalone"]
              element.attributes[:standalone] =
                child.attributes["standalone"]
            end
          end

          child.parent = element if child.is_a?(::Ox::Node)
          element.nodes ||= []
          element.nodes << child

          # Mark document if EntityReference is added (avoids tree scan in serialize)
          if child.is_a?(::Moxml::Adapter::CustomizedOx::EntityReference)
            root = element
            while root.is_a?(::Ox::Node) && root.parent
              root = root.parent
            end
            attachments.set(root, :has_entity_refs, true) if root
          end
        end

        def add_previous_sibling(node, sibling)
          return unless (parent = parent(node))

          if sibling.is_a?(::Ox::Node)
            sibling.parent&.nodes&.delete(sibling)
            sibling.parent = parent
          end
          idx = parent.nodes.index(node)
          parent.nodes.insert(idx, sibling) if idx
        end

        def add_next_sibling(node, sibling)
          return unless (parent = parent(node))

          if sibling.is_a?(::Ox::Node)
            sibling.parent&.nodes&.delete(sibling)
            sibling.parent = parent
          end
          idx = parent.nodes.index(node)
          parent.nodes.insert(idx + 1, sibling) if idx
        end

        def remove(node)
          return node.clear if node.is_a?(String)

          return unless parent(node)

          # Special handling for declarations on Ox documents
          if parent(node).is_a?(::Ox::Document) && node.is_a?(::Ox::Instruct) && node.target == "xml"
            # Clear declaration attributes from document
            doc = parent(node)
            doc.attributes&.delete(:version)
            doc.attributes&.delete(:encoding)
            doc.attributes&.delete(:standalone)
          end

          parent(node).nodes.delete(unpatch_node(node))
        end

        def replace(node, new_node)
          if node.is_a?(String) && new_node.is_a?(String)
            return node.replace(new_node)
          end
          # There are other cases:
          # when node is a String and new_node isn't
          # when node isn't a String, and new_node is a String

          return unless (parent = parent(node))

          new_node.parent = parent if new_node.is_a?(::Ox::Node)
          idx = parent.nodes.index(node)
          parent.nodes[idx] = new_node if idx
        end

        def replace_children(node, new_children)
          node.remove_children_by_path("*")
          new_children.each do |child|
            child.parent = node if child.is_a?(::Ox::Node)
            node << child
          end
          node
        end

        def assign_parents(node, parent = nil)
          node.parent = parent if node.respond_to?(:parent=) && parent
          return unless node.respond_to?(:nodes)

          node.nodes&.each do |child|
            assign_parents(child, node)
          end
        end

        def validate_single_root(document)
          elements = document.nodes&.grep(::Ox::Element) || []
          return unless elements.size > 1

          raise Moxml::ParseError.new(
            "Multiple root elements found",
            source: nil,
          )
        end

        def text_content(node)
          return "" if node.nil?

          case node
          when String then node.to_s
          when ::Moxml::Adapter::CustomizedOx::Text then node.value
          when ::Moxml::Adapter::CustomizedOx::EntityReference then ""
          else
            return "" unless node.is_a?(::Ox::Element) || node.is_a?(::Ox::Document)

            node.nodes.map do |n|
              text_content(n)
            end.join
          end
        end

        def inner_text(node)
          return "" unless node.is_a?(::Ox::Element) || node.is_a?(::Ox::Document)

          node.nodes.grep(String).join
        end

        def set_text_content(node, content)
          case node
          when String then node.replace(content.to_s)
          when ::Ox::Element then node.replace_text(content.to_s)
          else
            node.value = content.to_s
          end
        end

        def cdata_content(node)
          node.value.to_s
        end

        def set_cdata_content(node, content)
          node.value = content.to_s
        end

        def comment_content(node)
          node.value.to_s
        end

        def set_comment_content(node, content)
          node.value = content.to_s
        end

        def processing_instruction_content(node)
          node.content.to_s
        end

        def set_processing_instruction_content(node, content)
          node.content = content.to_s
        end

        def namespace_prefix(namespace)
          namespace.prefix
        end

        def namespace_uri(namespace)
          namespace.uri
        end

        def namespace_definitions(node)
          ([node] + ancestors(node)).reverse.each_with_object({}) do |n, namespaces|
            next unless n.is_a?(::Ox::Element) && n.attributes

            n.attributes.each do |name, value|
              next unless name.to_s.start_with?("xmlns")

              namespaces[name] = ::Moxml::Adapter::CustomizedOx::Namespace.new(
                name, value, n
              )
            end
          end.values
        end

        # Doctype accessor methods
        # Ox stores DOCTYPE as a string, so we parse it
        def doctype_name(native)
          # Parse: "name PUBLIC \"external_id\" \"system_id\"" or "name SYSTEM \"system_id\""
          value = native.value.to_s.strip
          # Extract the first word (the name)
          value.split(/\s+/).first
        end

        def doctype_external_id(native)
          value = native.value.to_s
          # Match PUBLIC "external_id"
          match = value.match(/PUBLIC\s+"([^"]*)"/)
          match ? match[1] : nil
        end

        def doctype_system_id(native)
          value = native.value.to_s
          # Match the last quoted string (system_id)
          # For PUBLIC: "name PUBLIC \"external_id\" \"system_id\""
          # For SYSTEM: "name SYSTEM \"system_id\""
          matches = value.scan(/"([^"]*)"/)
          matches.last&.first
        end

        def xpath(node, expression, namespaces = {})
          # Translate common XPath patterns to Ox locate() syntax
          locate_expr = translate_xpath_to_locate(expression, namespaces)

          # Ox's locate() works differently on documents vs elements
          # For relative descendant searches on elements, we need special handling
          if expression.start_with?(".//") && node.is_a?(::Ox::Element)
            # Manually search descendants for relative paths from elements
            element_name = locate_expr.sub("?/", "")
            results = []
            traverse(node) do |n|
              next unless n.is_a?(::Ox::Element)

              results << n if n.name == element_name || element_name.empty?
            end
            return results.map do |n|
              patch_node(n, find_parent_in_tree(n, node))
            end
          end

          # Use Ox's locate method for other cases
          results = node.locate(locate_expr)

          # Wrap results and set their parents by finding them in the tree
          results.map { |n| patch_node(n, find_parent_in_tree(n, node)) }
        rescue StandardError => e
          raise Moxml::XPathError.new(
            "XPath translation failed: #{e.message}",
            expression: expression,
            adapter: "Ox",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = {})
          xpath(node, expression, namespaces)&.first
        end

        def serialize(node, options = {})
          # Fast path: skip EntityReference scan for documents (most common case)
          if node.is_a?(::Ox::Document) &&
              !attachments.get(node, :has_entity_refs)
            return serialize_standard(node, options)
          end

          if tree_has_entity_references?(node)
            serialize_custom(node, options)
          else
            serialize_standard(node, options)
          end
        end

        def has_declaration?(native_doc, _wrapper)
          # Ox stores declaration in document attributes
          native_doc[:version] || native_doc[:encoding] || native_doc[:standalone]
        end

        private

        def serialize_standard(node, options = {})
          output = ""
          if node.is_a?(::Ox::Document)
            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  else
                                    node[:version] || node[:encoding] || node[:standalone]
                                  end

            if should_include_decl
              version = node[:version] || "1.0"
              encoding = options[:encoding] || node[:encoding]
              standalone = node[:standalone]

              decl = create_native_declaration(version, encoding, standalone)
              output = ::Ox.dump(::Ox::Document.new << decl).strip
            end
          end

          ox_options = {
            indent: -1,
            with_instructions: true,
            encoding: options[:encoding],
            no_empty: options[:expand_empty],
          }
          output + ::Ox.dump(node, ox_options)
        end

        def tree_has_entity_references?(node)
          case node
          when ::Moxml::Adapter::CustomizedOx::EntityReference
            true
          when ::Ox::Element
            node.nodes&.any? do |child|
              tree_has_entity_references?(child)
            end || false
          when ::Ox::Document
            node.nodes&.any? do |child|
              tree_has_entity_references?(child)
            end || false
          else
            false
          end
        end

        def serialize_custom(node, options = {})
          output = +""
          if node.is_a?(::Ox::Document)
            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  else
                                    node[:version] || node[:encoding] || node[:standalone]
                                  end
            if should_include_decl
              version = node[:version] || "1.0"
              encoding = options[:encoding] || node[:encoding]
              standalone = node[:standalone]
              output << "<?xml version=\"#{version}\""
              output << " encoding=\"#{encoding}\"" if encoding
              output << " standalone=\"#{standalone}\"" if standalone
              output << "?>"
            end
            (node.nodes || []).each do |child|
              output << serialize_node_custom(child)
            end
          else
            output << serialize_node_custom(node)
          end
          output
        end

        def serialize_node_custom(node)
          case node
          when ::Ox::Element then serialize_element_custom(node)
          when String then escape_xml_text(node)
          when ::Moxml::Adapter::CustomizedOx::Text then escape_xml_text(node.value)
          when ::Moxml::Adapter::CustomizedOx::EntityReference then "&#{node.name};"
          when ::Ox::CData then "<![CDATA[#{node.value}]]>"
          when ::Ox::Comment then "<!--#{node.value}-->"
          when ::Ox::Instruct then "<?#{node.target} #{node.value || ''}?>"
          when ::Ox::DocType then "<!DOCTYPE #{node.value}>"
          else ""
          end
        end

        def serialize_element_custom(elem)
          output = "<#{elem.name}"
          elem.attributes.each do |name, value|
            output << " #{name}=\"#{escape_xml_attribute(value.to_s)}\""
          end

          if elem.nodes.nil? || elem.nodes.empty?
            output << "/>"
            return output
          end

          output << ">"
          elem.nodes.each do |child|
            output << serialize_node_custom(child)
          end
          output << "</#{elem.name}>"
          output
        end

        def escape_xml_text(text)
          text.to_s.gsub(/[<>&]/) do |match|
            case match
            when "<" then "&lt;"
            when ">" then "&gt;"
            when "&" then "&amp;"
            end
          end
        end

        def escape_xml_attribute(value)
          value.to_s.gsub(/[<>&"]/) do |match|
            case match
            when "<" then "&lt;"
            when ">" then "&gt;"
            when "&" then "&amp;"
            when '"' then "&quot;"
            end
          end
        end

        # Translate a subset of XPath to Ox locate() syntax
        # Supports: //element, /path/to/element, .//element, element[@attr]
        # Note: Ox locate() doesn't support namespace prefixes in the path
        def translate_xpath_to_locate(xpath, namespaces = {})
          expr = xpath.dup

          # Strip namespace prefixes from element names
          # XPath: //ns:element → locate: element
          if namespaces && !namespaces.empty?
            namespaces.each_key do |prefix|
              expr = expr.gsub("/#{prefix}:", "/")
              expr = expr.gsub("/*#{prefix}:", "/*")
              expr = expr.gsub("//*#{prefix}:", "//")
              expr = expr.gsub("//#{prefix}:", "//")
              expr = expr.gsub("///#{prefix}:", "///")
            end
          end

          # Remove any remaining namespace prefixes
          # Use possessive quantifier to prevent ReDoS
          expr = expr.gsub(/[a-zA-Z_][\w-]*+:/, "")

          # Remove attribute predicates for now - we'll filter manually
          # Save the attribute name if present
          expr = expr.gsub(/\[@(\w+)\]/, "")

          # XPath: //element → locate: ?/element (any depth)
          # Note: In Ox, ?/ means "any path"
          expr = expr.sub(%r{^//}, "?/") if expr.start_with?("//")

          # XPath: .//element → locate: ?/element (relative any depth)
          # For relative paths from an element, we still use ?/ which searches
          # descendants
          expr = expr.sub(%r{^\.//}, "?/") if expr.start_with?(".//")

          # XPath: /root/child → locate: root/child (absolute path)
          # Remove leading / for Ox
          expr = expr.sub(%r{^/}, "")

          # XPath: ./element → locate: element (direct child, just remove ./)
          expr.sub(%r{^\./}, "")
        end

        # Find the actual parent of a node by searching the tree
        def find_parent_in_tree(target_node, search_root)
          # Start from the document root if we have a document
          root = search_root.is_a?(::Ox::Document) ? search_root : document(search_root)

          result = nil
          traverse(root) do |node|
            next unless node.is_a?(::Ox::Element) || node.is_a?(::Ox::Document)

            node.nodes&.each do |child|
              if child.equal?(target_node)
                result = node
                break
              end
            end
            break if result
          end
          result
        end

        def traverse(node, &block)
          return unless node

          yield node
          return unless node.is_a?(::Ox::Element) || node.is_a?(::Ox::Document)

          node.nodes&.each { |child| traverse(child, &block) }
        end
      end
    end

    # Bridge between Ox SAX and Moxml SAX
    #
    # Translates Ox::Sax events to Moxml::SAX::Handler events.
    # Ox has a unique SAX pattern where attributes are delivered AFTER start_element.
    #
    # @private
    class OxSAXBridge
      def initialize(handler)
        @handler = handler
        @pending_attrs = {}
        @pending_element_name = nil
        @element_started = false
        @document_started = false
      end

      # Ox delivers attributes AFTER start_element
      def attr(name, value)
        @pending_attrs[name] = value
      end

      # Called when element starts (but attributes come AFTER this)
      def start_element(name)
        # If we had a previous element waiting, we need to finalize it first
        if @pending_element_name
          finalize_pending_element
        end

        # Store this element name (convert symbol to string)
        @pending_element_name = name.to_s
        @element_started = true

        # Call on_start_document if this is the first element
        unless @document_started
          @handler.on_start_document
          @document_started = true
        end
      end

      def end_element(name)
        # Finalize any pending element before ending
        if @pending_element_name
          finalize_pending_element
        end

        # Convert symbol to string
        @handler.on_end_element(name.to_s)
      end

      # Ox only has text() - no separate CDATA, comment, or PI events
      def text(string)
        # Finalize any pending element before text
        if @pending_element_name
          finalize_pending_element
        end

        @handler.on_characters(string)
      end

      def error(message, line, column)
        error = Moxml::ParseError.new(message, line: line, column: column)
        @handler.on_error(error)
      end

      # Called at end of parsing (not automatically by Ox)
      def end_document
        # Finalize any pending element
        if @pending_element_name
          finalize_pending_element
        end

        @handler.on_end_document if @document_started
      end

      private

      def finalize_pending_element
        # Separate namespace declarations from regular attributes
        attr_hash = {}
        namespaces_hash = {}

        @pending_attrs.each do |attr_name, attr_value|
          if attr_name.to_s.start_with?("xmlns")
            # Namespace declaration
            prefix = if attr_name.to_s == "xmlns"
                       nil
                     else
                       attr_name.to_s.sub(
                         "xmlns:", ""
                       )
                     end
            namespaces_hash[prefix] = attr_value
          else
            attr_hash[attr_name.to_s] = attr_value
          end
        end

        @handler.on_start_element(@pending_element_name, attr_hash,
                                  namespaces_hash)

        # Clear for next element
        @pending_attrs = {}
        @pending_element_name = nil
      end
    end
  end
end
