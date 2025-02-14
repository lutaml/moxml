# frozen_string_literal: true

require_relative "base"
require "rexml/document"
require "rexml/xpath"
require "rexml/formatters/pretty"
require "set"

module Moxml
  module Adapter
    # Custom REXML formatter that fixes indentation and wrapping issues
    class CustomFormatter < ::REXML::Formatters::Pretty
      def initialize(indentation: 2, self_close_empty: false)
        @indentation = " " * indentation
        @level = 0
        @compact = true
        @width = -1 # Disable line wrapping
        @self_close_empty = self_close_empty
      end

      def write_element(node, output)
        # output << ' ' * @level
        output << "<#{node.expanded_name}"
        write_attributes(node, output)
        
        if node.children.empty? && @self_close_empty
          output << "/>"
          return
        end
        
        output << ">"
        
        # Check for mixed content
        has_text = node.children.any? { |c| c.is_a?(::REXML::Text) && !c.to_s.strip.empty? }
        has_elements = node.children.any? { |c| c.is_a?(::REXML::Element) }
        mixed = has_text && has_elements
        
        # Handle children based on content type
        unless node.children.empty?
          unless mixed
            @level += @indentation.length
          end
          
          node.children.each_with_index do |child, index|
            # Skip insignificant whitespace
            next if child.is_a?(::REXML::Text) && 
                   child.to_s.strip.empty? && 
                   !(child.next_sibling.nil? && child.previous_sibling.nil?)
            
            # Indent non-text nodes in non-mixed content
            # if !mixed && !child.is_a?(::REXML::Text)
            #   output << ' ' * @level
            # end
            
            write(child, output)
            
            # Add newlines between elements in non-mixed content
            # if !mixed && !child.is_a?(::REXML::Text) && index < node.children.size - 1
            #   output << "\n"
            # end
          end
          
          # Reset indentation for closing tag in non-mixed content
          unless mixed
            @level -= @indentation.length
            # output << ' ' * @level
          end
        end
        
        output << "</#{node.expanded_name}>"
        # output << "\n" unless mixed
      end

      def write_text(node, output)
        text = node.to_s
        return if text.empty?
        
        # Determine content context
        parent = node.parent
        return unless parent
        
        has_element_siblings = parent.elements.size > 0
        is_only_child = parent.children.size == 1
        is_whitespace = text.strip.empty?
        
        # Skip purely formatting whitespace between elements
        return if is_whitespace && 
                 has_element_siblings && 
                 !is_only_child
        
        # Determine if we're in mixed content
        mixed = has_element_siblings && !is_whitespace
        
        # Handle text
        if is_whitespace
          # Preserve significant whitespace
          output << text
        elsif mixed
          # In mixed content, preserve exact text without indentation
          output << escape_text(text)
        else
          # Normal text content
          # output << ' ' * @level if !mixed
          output << escape_text(text) #.strip
          # output << "\n" if !mixed
        end
      end

      def escape_text(text)
        text.to_s.gsub(/[<>&]/) do |match|
          case match
          when '<' then '&lt;'
          when '>' then '&gt;'
          when '&' then '&amp;'
          end
        end
      end

      private

      def find_significant_sibling(node, direction)
        method = direction == :next ? :next_sibling : :previous_sibling
        sibling = node.send(method)
        while sibling && sibling.is_a?(::REXML::Text) && sibling.to_s.strip.empty?
          sibling = sibling.send(method)
        end
        sibling
      end

      def write_cdata(node, output)
        # output << ' ' * @level
        output << "<![CDATA["
        output << node.to_s.gsub("]]>", "]]]]><![CDATA[>")
        output << "]]>"
        # output << "\n"
      end

      def write_comment(node, output)
        # output << ' ' * @level
        output << "<!--"
        output << node.to_s
        output << "-->"
        # output << "\n"
      end

      def write_instruction(node, output)
        # output << ' ' * @level
        output << "<?"
        output << node.target
        output << " "
        output << node.content if node.content
        output << "?>"
        # output << "\n"
      end

      def write_document(node, output)
        node.children.each do |child|
          write(child, output)
          # output << "\n" unless child == node.children.last
        end
      end

      def write_doctype(node, output)
        output << "<!DOCTYPE "
        output << node.name
        output << " "
        output << node.external_id if node.external_id
        output << ">"
        # output << "\n"
      end

      def write_declaration(node, output)
        output << "<?xml"
        output << %( version="#{node.version}") if node.version
        output << %( encoding="#{node.encoding.to_s.upcase}") if node.encoding
        output << %( standalone="#{node.standalone}") if node.standalone
        output << "?>"
        # output << "\n"
      end

      def write_attributes(node, output)
        # First write namespace declarations
        node.attributes.each do |name, attr|
          if name.to_s.start_with?('xmlns:') || name.to_s == 'xmlns'
            value = attr.respond_to?(:value) ? attr.value : attr
            output << " #{name}=\"#{value}\""
          end
        end

        # Then write regular attributes
        node.attributes.each do |name, attr|
          next if name.to_s.start_with?('xmlns:') || name.to_s == 'xmlns'
          
          output << " "
          if attr.respond_to?(:prefix) && attr.prefix
            output << "#{attr.prefix}:#{attr.name}"
          else
            output << name.to_s
          end
          
          output << "=\""
          value = attr.respond_to?(:value) ? attr.value : attr
          output << escape_attribute_value(value.to_s)
          output << "\""
        end
      end

      def escape_attribute_value(value)
        value.to_s.gsub(/[<>&"']/) do |match|
          case match
          when '<' then '&lt;'
          when '>' then '&gt;'
          when '&' then '&amp;'
          when '"' then '&quot;'
          # when "'" then '&apos;'
          end
        end
      end
    end

    # Wrapper to provide .native method expected by tests
    class RexmlWrapper
      attr_reader :native
      
      def initialize(native_obj)
        @native = native_obj
      end
      
      def method_missing(method, *args, &block)
        if method == :text && @native.is_a?(::REXML::Text)
          @native.value #.strip
        elsif method == :to_xml
          if @native.is_a?(::REXML::Attribute)
            value = escape_attribute_value(@native.value.to_s)
            prefix = @native.prefix ? "#{@native.prefix}:" : ""
            %{#{prefix}#{@native.name}="#{value}"}
          elsif @native.is_a?(String)
            escape_attribute_value(@native.to_s)
          else
            @native.to_s
          end
        elsif method == :value
          if @native.is_a?(::REXML::Attribute)
            @native.value
          elsif @native.is_a?(String)
            @native
          end
        elsif method == :value= && @native.is_a?(::REXML::Attribute)
          @native.remove
          element = @native.element
          name = @native.expanded_name
          prefix = @native.prefix
          value = args.first.to_s
          
          # Remove old attribute
          @native.remove
          
          if prefix
            # Find namespace URI in current scope
            current = element
            while current
              if current.respond_to?(:attributes)
                ns_attr = current.attributes["xmlns:#{prefix}"]
                if ns_attr
                  # Create namespaced attribute
                  attr = ::REXML::Attribute.new(name, value)
                  attr.add_namespace(prefix, ns_attr.value)
                  element.add_attribute(attr)
                  @native = attr
                  break
                end
              end
              current = current.parent
            end
            # If no namespace found, create without namespace
            if !current
              element.add_attribute(name, value)
              @native = element.attributes[name]
            end
          else
            # Regular attribute
            element.add_attribute(name, value)
            @native = element.attributes[name]
          end
        else
          @native.send(method, *args, &block)
        end
      end
      
      def respond_to_missing?(method, include_private = false)
        if method == :text && @native.is_a?(::REXML::Text)
          true
        elsif method == :to_xml
          true
        elsif method == :value && (@native.is_a?(::REXML::Attribute) || @native.is_a?(String))
          true
        elsif method == :value= && @native.is_a?(::REXML::Attribute)
          true
        else
          @native.respond_to?(method, include_private)
        end
      end

      def ==(other)
        return false unless other.is_a?(RexmlWrapper) || other.is_a?(::REXML::Element)
        if @native.is_a?(::REXML::Attribute) && other.respond_to?(:native) && other.native.is_a?(::REXML::Attribute)
          @native.value == other.native.value && @native.name == other.native.name
        else
          other_native = other.is_a?(RexmlWrapper) ? other.native : other
          @native == other_native
        end
      end

      private

      def escape_attribute_value(value)
        value.to_s.gsub(/[<>&"']/) do |match|
          case match
          when '<' then '&lt;'
          when '>' then '&gt;'
          when '&' then '&amp;'
          when '"' then '&quot;'
          when "'" then '&apos;'
          end
        end
      end
    end

    class Rexml < Base
      class << self
        def parse(xml, options = {})
          doc = begin
            doc = ::REXML::Document.new(xml.to_s)
            doc
          rescue ::REXML::ParseException => e
            if options[:strict]
              raise Moxml::ParseError.new(e.message, line: e.line)
            else
              create_document
            end
          end
          DocumentBuilder.new(Context.new(:rexml)).build(doc)
        end

        def create_document
          ::REXML::Document.new
        end

        def create_native_element(name)
          ::REXML::Element.new(name.to_s)
        end

        def create_native_text(content)
          ::REXML::Text.new(content.to_s, true, nil)
        end

        def create_native_cdata(content)
          ::REXML::CData.new(content.to_s)
        end

        def create_native_comment(content)
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
            parts.concat(["PUBLIC", %("#{external_id}")])
            parts << %("#{system_id}") if system_id
          elsif system_id
            parts.concat(["SYSTEM", %("#{system_id}")])
          end
          
          ::REXML::DocType.new(parts.join(" "))
        end

        def set_root(doc, element)
          doc = unwrap(doc)
          element = unwrap(element)
          doc.add_element(element)
        end

        def node_type(node)
          node = unwrap(node)
          case node
          when ::REXML::Document then :document
          when ::REXML::Element then :element
          when ::REXML::CData then :cdata
          when ::REXML::Text then :text
          when ::REXML::Comment then :comment
          when ::REXML::Instruction then :processing_instruction
          when ::REXML::DocType then :doctype
          when ::REXML::XMLDecl then :declaration
          else :unknown
          end
        end

        def set_node_name(node, name)
          node = unwrap(node)
          case node
          when ::REXML::Element
            node.name = name.to_s
          when ::REXML::Instruction
            node.target = name.to_s
          end
        end

        def node_name(node)
          node = unwrap(node)
          case node
          when ::REXML::Element
            node.name
          when ::REXML::DocType
            node.name
          when ::REXML::XMLDecl
            'xml'
          when ::REXML::Instruction
            node.target
          else
            nil
          end
        end

        def children(node)
          node = unwrap(node)
          return [] unless node.respond_to?(:children)
          
          # Get all children and filter out empty text nodes between elements
          result = node.children.reject do |child|
            child.is_a?(::REXML::Text) && 
            child.to_s.strip.empty? && 
            !(child.next_sibling.nil? && child.previous_sibling.nil?)
          end
          
          # Ensure uniqueness by object_id to prevent duplicates
          result.uniq(&:object_id).map { |child| wrap(child) }
        end

        def parent(node)
          node = unwrap(node)
          wrap(node.parent)
        end

        def next_sibling(node)
          node = unwrap(node)
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
          
          wrap(current)
        end

        def previous_sibling(node)
          node = unwrap(node)
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
          
          wrap(current)
        end

        def document(node)
          node = unwrap(node)
          wrap(node.document)
        end

        def root(document)
          document = unwrap(document)
          wrap(document.root)
        end

        def attributes(element)
          element = unwrap(element)
          return [] unless element.respond_to?(:attributes)
          # Only return non-namespace attributes
          element.attributes.reject { |name, _| name.to_s.start_with?("xmlns") }.map { |_, attr| 
            wrap(attr)
          }
        end

        def attribute_element(attribute)
          attribute = unwrap(attribute)
          wrap(attribute.element)
        end

        def set_attribute(element, name, value)
          element = unwrap(element)
          # Handle namespaced attributes
          prefix, local_name = name.to_s.split(':', 2)
          if local_name
            # Create namespaced attribute
            attr = ::REXML::Attribute.new(local_name, value.to_s)
            ns_uri = element.namespace(prefix)
            attr.add_namespace(prefix, ns_uri) if ns_uri
            element.add_attribute(attr)
          else
            # Create regular attribute
            element.add_attribute(name.to_s, value.to_s)
          end
        end

        def get_attribute(element, name)
          element = unwrap(element)
          # Handle namespaced attributes
          prefix, local_name = name.to_s.split(':', 2)
          if local_name
            attr = element.attributes["#{prefix}:#{local_name}"]
          else
            attr = element.attributes[name.to_s]
          end
          return nil unless attr
          wrap(attr)
        end

        def get_attribute_value(element, name)
          element = unwrap(element)
          # Handle namespaced attributes
          prefix, local_name = name.to_s.split(':', 2)
          
          if local_name
            # Look for namespaced attribute
            attr_name = "#{prefix}:#{local_name}"
            attr = element.attributes[attr_name]
            return nil unless attr
            value = attr.is_a?(String) ? attr : attr.value
            escape_attribute_value(value.to_s)
          else
            # Look for regular attribute
            attr = element.attributes[name.to_s]
            return nil unless attr
            value = attr.is_a?(String) ? attr : attr.value
            escape_attribute_value(value.to_s)
          end
        end

        def escape_attribute_value(value)
          value.to_s.gsub(/[<>&"']/) do |match|
            case match
            when '<' then '&lt;'
            when '>' then '&gt;'
            when '&' then '&amp;'
            when '"' then '&quot;'
            when "'" then '&apos;'
            end
          end
        end

        def remove_attribute(element, name)
          element = unwrap(element)
          element.delete_attribute(name.to_s)
        end

        def add_child(element, child)
          element = unwrap(element)
          child = unwrap(child)
          case child
          when String
            element.add_text(child)
          else
            element.add(child)
          end
        end

        def add_previous_sibling(node, sibling)
          node = unwrap(node)
          sibling = unwrap(sibling)
          parent = node.parent
          parent.insert_before(node, sibling)
        end

        def add_next_sibling(node, sibling)
          node = unwrap(node)
          sibling = unwrap(sibling)
          parent = node.parent
          parent.insert_after(node, sibling)
        end

        def remove(node)
          node = unwrap(node)
          node.remove
        end

        def replace(node, new_node)
          node = unwrap(node)
          new_node = unwrap(new_node)
          node.replace_with(new_node)
        end

        def replace_children(element, children)
          element = unwrap(element)
          element.children.each(&:remove)
          children.each { |child| element.add(unwrap(child)) }
        end

        def declaration_attribute(node, name)
          node = unwrap(node)
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
          node = unwrap(node)
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
          node = unwrap(node)
          node.string
        end

        def set_comment_content(node, content)
          node = unwrap(node)
          node.string = content.to_s
        end

        def cdata_content(node)
          node = unwrap(node)
          node.value
        end

        def set_cdata_content(node, content)
          node = unwrap(node)
          node.value = content.to_s
        end

        def processing_instruction_target(node)
          node = unwrap(node)
          node.target
        end

        def processing_instruction_content(node)
          node = unwrap(node)
          node.content
        end

        def set_processing_instruction_content(node, content)
          node = unwrap(node)
          node.content = content.to_s
        end

        def text_content(node)
          node = unwrap(node)
          case node
          when ::REXML::Text, ::REXML::CData
            node.value.to_s
          when ::REXML::Element
            # Get all text nodes, filter out duplicates, and join
            text_nodes = node.texts.uniq(&:object_id)
            text_nodes.map(&:value).join
          end
        end

        def inner_text(node)
          node = unwrap(node)
          # Get direct text children only, filter duplicates
          text_children = node.children
            .select { |c| c.is_a?(::REXML::Text) }
            .uniq(&:object_id)
          text_children.map(&:value).join
        end

        def set_text_content(node, content)
          node = unwrap(node)
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

        def create_native_namespace(element, prefix, uri)
          element = unwrap(element)
          prefix = prefix.to_s
          ns_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
          attr = ::REXML::Attribute.new(ns_name, uri)
          element.add_attribute(attr)
          [prefix, uri]
        end

        def set_namespace(element, namespace)
          element = unwrap(element)
          prefix, uri = namespace
          ns_name = prefix.to_s.empty? ? "xmlns" : "xmlns:#{prefix}"
          attr = ::REXML::Attribute.new(ns_name, uri)
          element.add_attribute(attr)
        end

        def namespace_prefix(node)
          node = unwrap(node)
          return nil unless node.respond_to?(:prefix)
          prefix = node.prefix
          prefix.to_s.empty? ? nil : prefix
        end

        def namespace_uri(node)
          node = unwrap(node)
          if node.respond_to?(:attributes)
            # Check for xmlns attribute first
            xmlns = node.attributes["xmlns"]
            return xmlns.value if xmlns
          end
          return nil unless node.respond_to?(:namespace)
          node.namespace
        end

        def namespace(node)
          node = unwrap(node)
          return nil unless node.respond_to?(:namespace) || node.respond_to?(:attributes)

          if node.is_a?(::REXML::Element)
            # For elements, get both explicit and inherited namespaces
            ns = node.namespace
            prefix = node.prefix
            
            if ns
              # If the element has an explicit namespace, use it
              return [prefix, ns]
            end

            # Check for a default namespace declaration on this element
            if node.attributes['xmlns']
              return [nil, node.attributes['xmlns'].value]
            end

            # Look for inherited namespaces
            current = node
            while current = current.parent
              if current.respond_to?(:attributes)
                if prefix && current.attributes["xmlns:#{prefix}"]
                  return [prefix, current.attributes["xmlns:#{prefix}"].value]
                elsif current.attributes['xmlns']
                  return [nil, current.attributes['xmlns'].value]
                end
              end
            end

          elsif node.is_a?(::REXML::Attribute)
            # Attributes don't inherit default namespaces
            prefix = node.prefix
            return nil unless prefix
            
            # Look for namespace declaration in scope
            current = node.element
            while current
              if current.respond_to?(:attributes)
                attr_name = "xmlns:#{prefix}"
                if current.attributes[attr_name]
                  return [prefix, current.attributes[attr_name].value]
                end
              end
              current = current.parent
            end
          end

          nil
        end

        def namespace_definitions(node)
          node = unwrap(node)
          return [] unless node.respond_to?(:attributes)
          
          result = []
          
          # Get all xmlns attributes from this node
          node.attributes.each do |name, attr|
            next unless name.to_s.start_with?("xmlns")
            value = attr.is_a?(String) ? attr : attr.value
            if name.to_s == "xmlns"
              result << [nil, value]
            else
              prefix = name.to_s.sub(/^xmlns:/, '')
              result << [prefix, value]
            end
          end

          # Add any namespaces from the element itself
          if node.respond_to?(:namespace) && node.namespace
            prefix = node.respond_to?(:prefix) ? node.prefix : nil
            unless result.any? { |p, _| p == prefix }
              result << [prefix, node.namespace]
            end
          end

          # Add inherited namespaces that aren't overridden
          if node.respond_to?(:parent) && node.parent
            parent_ns = namespace_definitions(node.parent)
            parent_ns.each do |prefix, uri|
              unless result.any? { |p, _| p == prefix }
                result << [prefix, uri]
              end
            end
          end

          result.uniq
        end

        def prepare_xpath_namespaces(node)
          ns = {}
          
          # Get all namespace definitions in scope
          all_ns = namespace_definitions(node)
          
          # Convert to XPath-friendly format
          all_ns.each do |prefix, uri|
            if prefix.nil? || prefix.empty?
              ns['xmlns'] = uri
            else
              ns[prefix] = uri
            end
          end
          
          ns
        end

        def xpath(node, expression, namespaces = {})
          node = unwrap(node)
          
          # Get the actual node to search from
          context = if node.respond_to?(:native)
            unwrap(node.native)
          else
            node
          end
          
          # If it's a document, use its root for context
          context = if context.is_a?(::REXML::Document)
            context.root || context
          else
            context
          end
          
          ns = prepare_xpath_namespaces(context).merge(namespaces || {})
          
          begin
            # Convert namespaces for REXML
            rexml_ns = {}
            
            # Handle namespaces
            ns.each do |prefix, uri|
              if prefix == 'xmlns'
                # Add default namespace with empty prefix for elements
                rexml_ns[''] = uri
                # Also add with xmlns prefix for backward compatibility
                rexml_ns['xmlns'] = uri
              else
                # Add other namespaces directly
                rexml_ns[prefix] = uri
              end
            end

            # Modify expression to handle default namespace correctly
            expr = expression.gsub(/\/(?!\/|@)([^\/\[\]]+)/) do |match|
              element = $1
              if element.include?(':')
                "/#{element}"  # Keep prefixed elements as-is
              else
                "/*[local-name()='#{element}']"  # Use local-name() for unprefixed elements
              end
            end
            expr = expr.sub(/^(?!\/)/, '/')  # Ensure relative paths work correctly
            
            # Handle absolute paths
            if expr.start_with?('//')
              # Keep descendant-or-self axis as-is
            elsif expr.start_with?('/')
              # Find document root
              root = context
              while root.respond_to?(:parent) && root.parent
                root = root.parent
              end
              context = root.is_a?(::REXML::Document) ? root.root || root : root
              expression = expression.sub(%r{^/}, '')
            end
            
            result = ::REXML::XPath.match(context, expression, rexml_ns)
            result.map { |n| wrap(n) }.uniq { |w| w.native.object_id }
          rescue ::REXML::ParseException => e
            raise Moxml::XPathError, e.message
          end
        end

        def at_xpath(node, expression, namespaces = {})
          results = xpath(node, expression, namespaces)
          results.first
        end

        def serialize(node, options = {})
          node = unwrap(node)
          output = String.new
          
          if node.is_a?(::REXML::Document)
            # Always include XML declaration
            decl = node.xml_decl || ::REXML::XMLDecl.new("1.0", options[:encoding] || "UTF-8")
            if options[:encoding]
              decl.encoding = options[:encoding]
            end
            output << "<?xml"
            output << %( version="#{decl.version}") if decl.version
            output << %( encoding="#{decl.encoding}") if decl.encoding
            output << %( standalone="#{decl.standalone}") if decl.standalone
            output << "?>"
            # output << "\n"
            
            if node.doctype
              node.doctype.write(output)
              # output << "\n"
            end
            
            # Write processing instructions
            node.children.each do |child|
              if child.is_a?(::REXML::Instruction)
                child.write(output)
                # output << "\n"
              end
            end
            
            if node.root
              write_with_formatter(node.root, output, options[:indent] || 2)
            end
          else
            write_with_formatter(node, output, options[:indent] || 2)
          end
          
          output.strip
        end

        private

        def write_with_formatter(node, output, indent = 2)
          formatter = CustomFormatter.new(indentation: indent, self_close_empty: false)
          formatter.write(node, output)
        end

        def unwrap(node)
          if node.respond_to?(:native)
            node.native.respond_to?(:native) ? node.native.native : node.native
          else
            node
          end
        end

        def wrap(node)
          node.nil? ? nil : RexmlWrapper.new(node)
        end
      end
    end
  end
end
