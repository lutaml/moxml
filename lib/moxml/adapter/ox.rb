# frozen_string_literal: true

return if RUBY_ENGINE == "opal"

require "ox"
require "stringio"

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
          existing_root = root(doc)
          element.parent = doc if element.is_a?(::Ox::Node)
          if existing_root
            # Replace the existing root element, preserving other children
            idx = doc.nodes.index(existing_root)
            doc.nodes[idx] = element
          else
            # No root yet, just append the element
            doc << element
          end
        end

        def parse(xml, options = {}, _context = nil)
          processed_xml = preprocess_entities(xml)
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

          ctx = _context || Context.new(context_adapter_name)
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
          ::Ox::Element.new(name)
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
          value = if external_id
                    "#{name} PUBLIC \"#{external_id}\" \"#{system_id}\""
                  elsif system_id
                    "#{name} SYSTEM \"#{system_id}\""
                  else
                    name.to_s
                  end
          ::Ox::DocType.new(value)
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
          return element unless element.is_a?(::Ox::Element) || element.is_a?(::Ox::Node)

          prefix = ns.prefix
          # attributes don't have attributes but can have a namespace prefix
          if element.is_a?(::Ox::Element)
            set_attribute(element, ns.expanded_prefix,
                          ns.uri)
          end
          element.name = [prefix,
                          element.name.delete_prefix("xmlns:")].compact.join(":")
          element
        end

        def namespace(element)
          prefix =
            if element.is_a?(::Moxml::Adapter::CustomizedOx::Attribute)
              element.prefix
            elsif element.name.include?(":")
              element.name.split(":").first
            end

          # Unprefixed attributes are in no namespace — the default
          # namespace declaration does not apply to attribute names
          # (Namespaces 1.0 §5.2). Unprefixed elements DO take it.
          return nil if element.is_a?(::Moxml::Adapter::CustomizedOx::Attribute) && prefix.nil?

          # Namespaces 1.0 §4: xml is prebound; no declaration required.
          if prefix == "xml"
            return ::Moxml::Adapter::CustomizedOx::Namespace.new(
              prefix, Moxml::AttributeResolver::XML_NAMESPACE_URI, element
            )
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
          when ::Moxml::Adapter::CustomizedOx::Namespace then :namespace
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
            child.parent = node if child.is_a?(::Ox::Element)
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
          attribute
        end

        def set_attribute_value(attribute, new_value)
          if new_value.nil?
            # Ox converts all values to strings
            remove_attribute(attribute.parent, attribute.name)
          else
            element = attribute.parent
            # Rekey by the expanded name (Ox hash keys carry the
            # prefix) and collapse any symbol/string spelling of the
            # same key, or a stale symbol key shadows the new value.
            expanded = attribute.expanded_name
            element.attributes.delete(expanded.to_sym)
            element.attributes[expanded] = new_value
            attribute.value = new_value
          end
          attribute
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

        def remove_attribute_native(attribute)
          expanded = attribute.expanded_name
          element = attribute.parent
          element.attributes.delete(expanded)
          element.attributes.delete(expanded.to_sym)
          attribute
        end

        def add_child(element, child)
          if element.is_a?(::Ox::Document) && child.is_a?(::Ox::Instruct) && child.target == "xml"
            element.attributes ||= {}
            element.attributes[:version] = child.attributes["version"] if child.attributes["version"]
            element.attributes[:encoding] = child.attributes["encoding"] if child.attributes["encoding"]
            element.attributes[:standalone] = child.attributes["standalone"] if child.attributes["standalone"]
            attachments.set(element, :decl_explicit, {
                              encoding: child.attributes.key?("encoding") ? child.attributes["encoding"] : nil,
                              standalone: child.attributes.key?("standalone") ? child.attributes["standalone"] : nil,
                            })
            return
          end

          child.parent = element if child.is_a?(::Ox::Node)
          element.nodes ||= []

          # Insert doctype before root element in document
          if element.is_a?(::Ox::Document) && child.is_a?(::Ox::DocType)
            root_idx = element.nodes.index { |n| n.is_a?(::Ox::Element) }
            if root_idx
              element.nodes.insert(root_idx, child)
            else
              element.nodes << child
            end
          else
            element.nodes << child
          end

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
          node.parent = parent if node.is_a?(::Ox::Element) && parent
          return unless node.is_a?(::Ox::Element) || node.is_a?(::Ox::Document)

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
          when ::Ox::CData then node.value.to_s
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
          return [] unless node.is_a?(::Ox::Element) && node.attributes

          namespaces = {}
          node.attributes.each do |name, value|
            name_s = name.to_s
            next unless name_s == "xmlns" || name_s.start_with?("xmlns:")

            namespaces[name] = ::Moxml::Adapter::CustomizedOx::Namespace.new(
              name, value, node
            )
          end
          namespaces.values
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

        # XPath runs through Moxml's pure-Ruby XPath 1.0 engine (shared
        # with HeadedOx and Leptris). Ox's locate() only covers a
        # small XPath subset; the engine provides all axes,
        # predicates, functions and variables.
        def xpath(node, expression, namespaces = {})
          wrapped = if node.is_a?(Moxml::Node)
                      node
                    else
                      Moxml::Node.wrap(node, Context.new(context_adapter_name))
                    end

          ast = XPath::Parser.parse(expression)
          proc = XPath::Compiler.compile_with_cache(ast, namespaces: namespaces)
          result = proc.call(wrapped)

          case result
          when Array
            dedupe_natives(result.map do |n|
              n.is_a?(Moxml::Node) ? n.native : n
            end)
          when NodeSet
            dedupe_natives(result.to_a.map(&:native))
          else
            result
          end
        rescue StandardError => e
          raise Moxml::XPathError.new(
            "XPath execution failed: #{e.message}",
            expression: expression,
            adapter: "Ox",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = {})
          result = xpath(node, expression, namespaces)
          result.is_a?(Array) ? result.first : result
        end

        def xpath_supported?
          true
        end

        # Identity-based dedup: uniq's value equality would collapse
        # equal String text nodes.
        def dedupe_natives(natives)
          seen = {}
          natives.select do |native|
            id = native.object_id
            if seen[id]
              false
            else
              seen[id] = true
            end
          end
        end

        # Adapter name used when wrapping bare native nodes; kept
        # overridable so HeadedOx wraps into its own adapter.
        def context_adapter_name
          :ox
        end

        def serialize(node, options = {})
          # CustomizedOx::Text subclasses ::Ox::Node so it can carry a @parent
          # back-reference, but that makes it unknown to Ox.dump's XML emitter,
          # which then falls back to generic object marshalling. Short-circuit
          # here with proper XML escaping.
          return XmlEmitter.escape_text(node.value) if node.is_a?(CustomizedOx::Text)

          needs_custom = needs_custom_serialize?(node)

          unless needs_custom
            return serialize_standard(node, options)
          end

          serialize_custom(node, options)
        end

        def needs_custom_serialize?(node)
          # Fast path: single CData with ]]>
          return true if node.is_a?(::Ox::CData) && node.value&.include?("]]>")

          # Only documents/elements can contain entity refs or CDATA issues
          return false unless node.is_a?(::Ox::Document) || node.is_a?(::Ox::Element)

          # Element serializes consult the owning document's cached
          # flags — a rescan per call made element to_xml ~30x slower
          # than document to_xml on plain documents.
          scan_root = node
          if node.is_a?(::Ox::Element) && (doc = document(node))
            return true if attachments.get(doc, :has_entity_refs)
            return true if attachments.get(doc, :has_cdata_end_markers)
            return false if attachments.key?(doc, :has_entity_refs) &&
              attachments.key?(doc, :has_cdata_end_markers)

            scan_root = doc
          end

          # One merged tree scan instead of two; flags cache on the
          # document either way.
          has_er, has_cdata = tree_scan_custom_needs(scan_root)
          if scan_root.is_a?(::Ox::Document)
            attachments.set(scan_root, :has_entity_refs, has_er)
            attachments.set(scan_root, :has_cdata_end_markers, has_cdata)
          end

          has_er || has_cdata
        end

        # Single walk collecting both custom-serialize triggers.
        def tree_scan_custom_needs(node)
          has_er = false
          has_cdata = false
          stack = [node]
          until stack.empty?
            current = stack.pop
            case current
            when ::Moxml::Adapter::CustomizedOx::EntityReference
              has_er = true
            when ::Ox::CData
              has_cdata = true if current.value&.include?("]]>")
            when ::Ox::Element, ::Ox::Document
              current.nodes&.each { |child| stack << child }
            end
            return [true, has_cdata] if has_er
          end
          [has_er, has_cdata]
        end

        def has_declaration?(native_doc, _wrapper)
          native_doc[:version] || native_doc[:encoding] || native_doc[:standalone]
        end

        def remove_declaration(native_doc)
          native_doc.attributes&.delete(:version)
          native_doc.attributes&.delete(:encoding)
          native_doc.attributes&.delete(:standalone)
          attachments.delete(native_doc, :decl_explicit)
        end

        private

        def resolve_decl_attr(node, attr, fallback)
          if attachments.key?(node, :decl_explicit)
            attachments.get(node, :decl_explicit)[attr]
          else
            node[attr] || fallback
          end
        end

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
              encoding = resolve_decl_attr(node, :encoding, options[:encoding])
              standalone = resolve_decl_attr(node, :standalone, nil)

              decl = create_native_declaration(version, encoding, standalone)
              output = ::Ox.dump(::Ox::Document.new << decl).strip
            end
          end

          ox_options = {
            indent: -1,
            with_instructions: false,
            encoding: options[:encoding],
            no_empty: options[:expand_empty],
          }
          output + ::Ox.dump(node, ox_options)
          # Fix CDATA ]]> end markers that Ox doesn't escape
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

        def tree_has_cdata_end_markers?(node)
          case node
          when ::Ox::CData
            node.value&.include?("]]>") || false
          when ::Ox::Element
            node.nodes&.any? do |child|
              tree_has_cdata_end_markers?(child)
            end || false
          when ::Ox::Document
            node.nodes&.any? do |child|
              tree_has_cdata_end_markers?(child)
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
              encoding = resolve_decl_attr(node, :encoding, options[:encoding])
              standalone = resolve_decl_attr(node, :standalone, nil)
              output << XmlEmitter.declaration_xml(version, encoding, standalone)
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
          when String then XmlEmitter.escape_text(node)
          when ::Moxml::Adapter::CustomizedOx::Text then XmlEmitter.escape_text(node.value)
          when ::Moxml::Adapter::CustomizedOx::EntityReference then "&#{node.name};"
          when ::Ox::CData then XmlEmitter.cdata(node.value)
          when ::Ox::Comment then "<!--#{node.value}-->"
          when ::Ox::Instruct then "<?#{node.target} #{node.value || ''}?>"
          when ::Ox::DocType then "<!DOCTYPE #{node.value}>"
          else ""
          end
        end

        def serialize_element_custom(elem)
          output = "<#{elem.name}"
          elem.attributes.each do |name, value|
            output << " #{name}=\"#{XmlEmitter.escape_attribute(value)}\""
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
      end
    end

    # Bridge between Ox SAX and Moxml SAX
    #
    # Translates Ox::Sax events to Moxml::SAX::Handler events.
    # Ox has a unique SAX pattern where attributes are delivered AFTER start_element.
    #
    # @private
    class OxSAXBridge
      include Moxml::SAX::NamespaceSplitter

      def initialize(handler)
        @handler = handler
        @pending_attrs = {}
        @pending_element_name = nil
        @element_started = false
        @document_started = false
      end

      # Ox delivers attributes AFTER start_element
      def attr(name, value)
        # Attributes arriving before the first start_element belong
        # to the XML declaration, not to any element
        @pending_attrs[name.to_s] = value if @pending_element_name
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
        attr_hash, ns_hash = split_attributes_and_namespaces(@pending_attrs)
        @handler.on_start_element(@pending_element_name, attr_hash, ns_hash)

        # Clear for next element
        @pending_attrs = {}
        @pending_element_name = nil
      end
    end
  end
end
