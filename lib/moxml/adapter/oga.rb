# frozen_string_literal: true

require "oga"

module Moxml
  module Adapter
    class Oga < Base
      # Sentinel that replaces "&amp;" before handing XML to Oga, then is
      # restored to "&" after parsing. Works around Oga's 3-pass entity
      # decoder (named -> decimal -> hex) which double-decodes inputs like
      # "&amp;#38;" — pass 1 turns "&amp;" into "&", then pass 2 combines
      # it with the trailing "#38;" to produce "&", violating XML 1.0
      # single-pass decoding semantics. Replacing "&amp;" with a non-"&"
      # sentinel prevents pass 2/3 from finding anything to combine.
      #
      # The default sentinel is three Unicode noncharacters (U+FDD0..U+FDEF
      # is the noncharacter block, explicitly reserved by Unicode for
      # internal use and never permitted in interchange data). Real XML
      # is forbidden from containing these — but inputs are not always
      # well-formed, so we always check the source for collision and
      # generate a unique marker if needed (see amp_marker_for).
      DEFAULT_AMP_MARKER = "\u{FDD0}\u{FDD1}\u{FDD2}"

      # The workarounds in this adapter depend on three Oga internals:
      # Attribute#@value, Attribute#@decoded, Text#@text, Text#@decoded.
      # Detect at load time whether the running Oga exposes these so the
      # adapter can degrade gracefully (and log a clear warning) if a
      # future Oga release renames or removes them.
      OGA_INTERNALS_SUPPORTED = begin
        probe_attr = ::Oga::XML::Attribute.new(name: "x", value: "v")
        probe_text = ::Oga::XML::Text.new(text: "t")
        probe_attr.instance_variable_defined?(:@value) &&
          probe_attr.instance_variable_defined?(:@decoded) &&
          probe_text.instance_variable_defined?(:@text) &&
          probe_text.instance_variable_defined?(:@decoded)
      rescue StandardError
        false
      end

      unless OGA_INTERNALS_SUPPORTED
        warn "[moxml] Oga internal ivars (@value/@text/@decoded) not detected " \
             "on Oga #{begin
               ::Oga::VERSION
             rescue StandardError
               '?'
             end} — entity-decoding " \
             "workarounds will fall back to public setters and may " \
             "double-decode '&amp;#NN;' inputs. Pin oga ~> 3.4."
      end

      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        # Replace "&amp;" with a sentinel that Oga's entity decoder won't
        # touch (it doesn't start with "&"). Skips regions where the XML
        # parser delivers content verbatim (CDATA, comments, processing
        # instructions, DOCTYPE declarations) — substituting inside any
        # of these would corrupt literal "&amp;" sequences (e.g. in an
        # <!ENTITY ...> body or a PI payload).
        #
        # Returns [processed_xml, marker]. `marker` is nil when no
        # substitution was performed (the input had no "&amp;" outside
        # verbatim blocks), and callers must skip restoration in that
        # case — otherwise legitimate user data matching the default
        # marker codepoints would be corrupted.
        def preprocess_amp_for_oga(xml)
          return [xml, nil] unless xml.is_a?(String) && xml.include?("&amp;")

          marker = amp_marker_for(xml)
          result = +""
          i = 0
          len = xml.length
          substituted = false
          while i < len
            block_start, terminator = next_verbatim_block(xml, i)

            if block_start.nil?
              chunk = xml[i..]
              substituted ||= chunk.include?("&amp;")
              result << chunk.gsub("&amp;", marker)
              break
            end

            chunk = xml[i...block_start]
            substituted ||= chunk.include?("&amp;")
            result << chunk.gsub("&amp;", marker)
            end_idx = find_block_terminator(xml, block_start, terminator)

            if end_idx.nil?
              # Unterminated declaration; copy the rest verbatim
              # (Oga's parser will surface the error).
              result << xml[block_start..]
              break
            end

            result << xml[block_start..(end_idx + terminator.length - 1)]
            i = end_idx + terminator.length
          end
          [result, substituted ? marker : nil]
        end

        # Choose a marker not present in the source XML. Falls back from
        # the default three-noncharacter sequence to other noncharacter
        # triples in U+FDD0..U+FDEF if the default appears in user data.
        # Real XML interchange data must not contain these codepoints,
        # but inputs are not always well-formed so we defend against
        # accidental collision.
        def amp_marker_for(xml)
          return DEFAULT_AMP_MARKER unless xml.include?(DEFAULT_AMP_MARKER)

          (0xFDD0..0xFDED).each do |start|
            triple = [start, start + 1, start + 2].pack("U*")
            return triple unless xml.include?(triple)
          end

          # Extreme fallback: extend with additional noncharacters until
          # the marker is unique to the input. U+FFFE is also a permanent
          # noncharacter.
          marker = DEFAULT_AMP_MARKER.dup
          marker << "\u{FFFE}" while xml.include?(marker)
          marker.freeze
        end

        # Locate the terminator for a verbatim block. For DOCTYPE blocks
        # the terminator may legally appear inside a quoted ExternalID
        # (e.g. `">"` or `"]>"` inside a SYSTEM/PUBLIC id, or inside an
        # <!ENTITY> body); scan quote-aware so those literal occurrences
        # are not mistaken for the real end. CDATA / comment / PI
        # terminators (`]]>`, `-->`, `?>`) cannot appear inside quoted
        # strings in their respective grammars, so a plain substring
        # search is fine for those.
        def find_block_terminator(xml, block_start, terminator)
          return xml.index(terminator, block_start) unless ["]>", ">"].include?(terminator)

          quote = nil
          i = block_start
          len = xml.length
          while i < len
            ch = xml[i]
            if quote
              quote = nil if ch == quote
            elsif DOCTYPE_QUOTES.include?(ch)
              quote = ch
            elsif (terminator == "]>" && ch == "]" && xml[i + 1] == ">") ||
                (terminator == ">" && ch == ">")
              return i
            end
            i += 1
          end
          nil
        end

        # Find the next region starting at or after `from` that the XML
        # parser delivers verbatim. Returns [start_idx, terminator] or
        # [nil, nil] if no such region remains.
        def next_verbatim_block(xml, from)
          candidates = {
            "<![CDATA[" => "]]>",
            "<!--" => "-->",
            "<?" => "?>",
            "<!DOCTYPE" => nil, # terminator computed dynamically
          }

          best_start = nil
          best_terminator = nil
          candidates.each do |opener, terminator|
            idx = xml.index(opener, from)
            next if idx.nil?
            next if best_start && idx >= best_start

            best_start = idx
            best_terminator = terminator || doctype_terminator(xml, idx)
          end
          [best_start, best_terminator]
        end

        DOCTYPE_QUOTES = ['"', "'"].freeze
        private_constant :DOCTYPE_QUOTES

        # DOCTYPE may include an internal subset "[ ... ]" after the
        # ExternalID. The terminator is "]>" if an unquoted "[" appears
        # before an unquoted ">", otherwise just ">". We scan
        # character-by-character tracking quoted strings (system/public
        # IDs use single or double quotes) so a literal "[" inside a
        # quoted ID is not mistaken for the internal subset opener.
        def doctype_terminator(xml, start_idx)
          quote = nil
          i = start_idx
          len = xml.length
          while i < len
            ch = xml[i]
            if quote
              quote = nil if ch == quote
            elsif DOCTYPE_QUOTES.include?(ch)
              quote = ch
            elsif ch == "["
              return "]>"
            elsif ch == ">"
              return ">"
            end
            i += 1
          end
          ">"
        end

        def set_root(doc, element)
          # Clear existing root element if any - Oga's NodeSet needs special handling
          # We need to manually remove elements since NodeSet doesn't support clear or delete_if
          elements_to_remove = doc.children.grep(::Oga::XML::Element)
          elements_to_remove.each { |elem| doc.children.delete(elem) }
          doc.children << element
        end

        def parse(xml, options = {}, _context = nil)
          processed_xml, marker = preprocess_amp_for_oga(preprocess_entities(xml))

          native_doc = begin
            ::Oga.parse_xml(processed_xml, strict: options[:strict])
          rescue LL::ParserError => e
            raise Moxml::ParseError.new(
              e.message,
              source: xml.is_a?(String) ? xml[0..100] : nil,
            )
          end

          restore_amp_in_tree!(native_doc, marker) if marker

          ctx = _context || Context.new(:oga)
          DocumentBuilder.new(ctx).build(native_doc)
        end

        # Walk the parsed tree and replace the per-input marker sentinels
        # with "&" in attribute values and text nodes. The marker was
        # inserted by preprocess_amp_for_oga to prevent Oga's broken
        # 3-pass entity decoder from double-decoding "&amp;#NN;".
        #
        # We use instance_variable_set instead of the public writers because
        # Oga's Attribute#value= and Text#text= reset the lazy @decoded flag,
        # which would cause the freshly-restored "&" to be re-fed into the
        # broken decoder on next read.
        def restore_amp_in_tree!(node, marker)
          return if marker.nil?

          # PI, Comment, and Doctype are intentionally omitted:
          # preprocess_amp_for_oga skips their source-text spans, so the
          # marker is never inserted into their payloads and there is
          # nothing to restore.
          case node
          when ::Oga::XML::Document
            node.children.each { |c| restore_amp_in_tree!(c, marker) }
          when ::Oga::XML::Element
            node.attributes.each { |attr| restore_amp_in_attribute!(attr, marker) }
            node.children.each { |c| restore_amp_in_tree!(c, marker) }
          when ::Oga::XML::Text, ::Oga::XML::Cdata
            restore_amp_in_text!(node, marker)
          end
        end

        def restore_amp_in_attribute!(attr, marker)
          value = attr.value # triggers Oga's lazy decode once
          return unless value.is_a?(String) && value.include?(marker)

          restored = value.gsub(marker, "&")
          if OGA_INTERNALS_SUPPORTED && attr.instance_variable_defined?(:@value)
            attr.instance_variable_set(:@value, restored)
            attr.instance_variable_set(:@decoded, true)
          else
            # Fallback for unknown Oga versions: use the public setter.
            # This resets @decoded and risks re-decoding on next read,
            # but is the best we can do without internal access.
            attr.value = restored
          end
        end

        def restore_amp_in_text!(node, marker)
          text = node.text # triggers Oga's lazy decode once
          return unless text.is_a?(String) && text.include?(marker)

          restored = text.gsub(marker, "&")
          if OGA_INTERNALS_SUPPORTED && node.instance_variable_defined?(:@text)
            node.instance_variable_set(:@text, restored)
            node.instance_variable_set(:@decoded, true)
          else
            node.text = restored
          end
        end

        # SAX parsing implementation for Oga
        #
        # @param xml [String, IO] XML to parse
        # @param handler [Moxml::SAX::Handler] Moxml SAX handler
        # @return [void]
        def sax_parse(xml, handler)
          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s
          xml_string, marker = preprocess_amp_for_oga(xml_string)

          bridge = OgaSAXBridge.new(handler, marker)

          # Manually call start_document (Oga doesn't)
          handler.on_start_document

          ::Oga.sax_parse_xml(bridge, xml_string)

          # Manually call end_document (Oga doesn't)
          handler.on_end_document
        rescue StandardError => e
          error = Moxml::ParseError.new(e.message)
          handler.on_error(error)
        end

        def create_document(_native_doc = nil)
          ::Oga::XML::Document.new
        end

        def create_native_element(name, _owner_doc = nil)
          ::Oga::XML::Element.new(name: name)
        end

        def create_native_text(content, _owner_doc = nil)
          text = ::Oga::XML::Text.new(text: preprocess_entities(content))
          # Mark as already-decoded so Oga's broken 3-pass entity decoder
          # doesn't mangle "&#NN;"-style literals on first read.
          if OGA_INTERNALS_SUPPORTED && text.instance_variable_defined?(:@decoded)
            text.instance_variable_set(:@decoded, true)
          end
          text
        end

        def create_native_entity_reference(name)
          text = ::Oga::XML::Text.new
          text.text = "#{self::ENTITY_MARKER}#{name};"
          attachments.set(text, :entity_name, name)
          text
        end

        def entity_reference_name(node)
          attachments.get(node, :entity_name)
        end

        def create_native_cdata(content, _owner_doc = nil)
          ::Oga::XML::Cdata.new(text: content)
        end

        def create_native_comment(content, _owner_doc = nil)
          ::Oga::XML::Comment.new(text: content)
        end

        def create_native_doctype(name, external_id, system_id)
          ::Oga::XML::Doctype.new(
            name: name, public_id: external_id, system_id: system_id,
            type: external_id ? "PUBLIC" : "SYSTEM"
          )
        end

        def create_native_processing_instruction(target, content)
          ::Oga::XML::ProcessingInstruction.new(name: target, text: content)
        end

        def create_native_declaration(version, encoding, standalone)
          attrs = {
            version: version,
            encoding: encoding,
            standalone: standalone,
          }.compact
          ::Moxml::Adapter::CustomizedOga::XmlDeclaration.new(attrs)
        end

        def declaration_attribute(declaration, attr_name)
          unless ::Moxml::Declaration::ALLOWED_ATTRIBUTES.include?(attr_name.to_s)
            return
          end

          declaration.public_send(attr_name)
        end

        def set_declaration_attribute(declaration, attr_name, value)
          unless ::Moxml::Declaration::ALLOWED_ATTRIBUTES.include?(attr_name.to_s)
            return
          end

          declaration.public_send("#{attr_name}=", value)
        end

        def create_native_namespace(element, prefix, uri)
          ns = element.available_namespaces[prefix]
          return ns unless ns.nil?

          # Oga creates an attribute and registers a namespace
          set_attribute(element,
                        [::Oga::XML::Element::XMLNS_PREFIX, prefix].compact.join(":"), uri)
          element.register_namespace(prefix, uri)
          ::Oga::XML::Namespace.new(name: prefix, uri: uri)
        end

        def set_namespace(element, ns_or_string)
          element.namespace_name = ns_or_string.to_s
        end

        def namespace(element)
          case element
          when ::Oga::XML::Element, ::Oga::XML::Attribute
            element.namespace
          end
        rescue NoMethodError
          # Oga attributes fail with NoMethodError:
          # undefined method `available_namespaces' for nil:NilClass
          nil
        end

        def processing_instruction_target(node)
          node.name
        end

        def node_type(node)
          case node
          when ::Oga::XML::Element then :element
          when ::Oga::XML::Text
            if attachments.key?(node, :entity_name)
              :entity_reference
            else
              :text
            end
          when ::Oga::XML::Cdata then :cdata
          when ::Oga::XML::Comment then :comment
          when ::Oga::XML::Attribute then :attribute
          when ::Oga::XML::Namespace then :namespace
          when ::Oga::XML::ProcessingInstruction then :processing_instruction
          when ::Oga::XML::Document then :document
          when ::Oga::XML::Doctype then :doctype
          else :unknown
          end
        end

        def node_name(node)
          node.name
        end

        def set_node_name(node, name)
          node.name = name
        end

        def children(node)
          all_children = []

          if node.is_a?(::Oga::XML::Document)
            all_children += [node.xml_declaration,
                             node.doctype].compact
          end

          return all_children unless node.is_a?(::Oga::XML::Node) || node.is_a?(::Oga::XML::Document)

          child_nodes = node.children.to_a
          # Filter out whitespace-only text nodes at document level only.
          # Document-level whitespace (between <?xml?> and <root>) is
          # formatting, not content, and differs across adapters.
          # Whitespace inside elements (e.g. "FigureA.1" spacing) is
          # meaningful and must be preserved.
          if node.is_a?(::Oga::XML::Document)
            child_nodes = child_nodes.reject do |child|
              child.is_a?(::Oga::XML::Text) && child.text.strip.empty?
            end
          end
          all_children + child_nodes
        end

        def adjacent_to_entity_reference?(node)
          entity_ref?(node.previous) || entity_ref?(node.next)
        end

        def entity_ref?(node)
          node.is_a?(::Oga::XML::Text) &&
            attachments.get(node, :entity_name)
        end

        def parent(node)
          node.parent if node.is_a?(::Oga::XML::Node)
        end

        def next_sibling(node)
          node.next
        end

        def previous_sibling(node)
          node.previous
        end

        def document(node)
          current = node
          current = current.parent while parent(current)

          current
        end

        def root(document)
          document.children.find { |node| node.is_a?(::Oga::XML::Element) }
        end

        def attribute_element(attr)
          attr.element
        end

        def attributes(element)
          return [] unless element.is_a?(::Oga::XML::Element)

          # remove attributes-namespaces
          element.attributes.reject do |attr|
            attr.name == ::Oga::XML::Element::XMLNS_PREFIX || attr.namespace_name == ::Oga::XML::Element::XMLNS_PREFIX
          end
        end

        def set_attribute(element, name, value)
          namespace_name = nil
          if name.to_s.include?(":")
            namespace_name, name = name.to_s.split(":",
                                                   2)
          end

          attr = ::Oga::XML::Attribute.new(
            name: name.to_s,
            namespace_name: namespace_name,
            value: preprocess_entities(value.to_s),
          )
          # Tell Oga's lazy decoder this value is already literal text and
          # must not be run through the broken 3-pass entity decoder; without
          # this, "&#38;" set by the user would be silently resolved to "&"
          # (and the trailing "#38;" lost) on first read.
          if OGA_INTERNALS_SUPPORTED && attr.instance_variable_defined?(:@decoded)
            attr.instance_variable_set(:@decoded, true)
          end
          element.add_attribute(attr)
        end

        def get_attribute(element, name)
          element.attribute(name.to_s)
        end

        def get_attribute_value(element, name)
          element[name.to_s]
        end

        def remove_attribute(element, name)
          attr = element.attribute(name.to_s)
          element.attributes.delete(attr) if attr
        end

        def add_child(element, child_or_text)
          child =
            if child_or_text.is_a?(String)
              create_native_text(child_or_text)
            else
              child_or_text
            end

          if element.is_a?(::Oga::XML::Document) &&
              child.is_a?(::Oga::XML::XmlDeclaration)
            attachments.set(element, :xml_declaration, child)
            return
          end

          # Insert doctype before root element in document
          if element.is_a?(::Oga::XML::Document) && child.is_a?(::Oga::XML::Doctype)
            root_idx = nil
            element.children.each_with_index do |n, i|
              if n.is_a?(::Oga::XML::Element)
                root_idx = i
                break
              end
            end
            if root_idx
              element.children.insert(root_idx, child)
              return
            end
          end

          element.children << child
        end

        def add_previous_sibling(node, sibling)
          if node.parent == sibling.parent
            # Oga doesn't manipulate children of the same parent
            dup_sibling = node.node_set.delete(sibling)
            index = node.node_set.index(node)
            node.node_set.insert(index, dup_sibling)
          else
            node.before(sibling)
          end
        end

        def add_next_sibling(node, sibling)
          if node.parent == sibling.parent
            # Oga doesn't manipulate children of the same parent
            dup_sibling = node.node_set.delete(sibling)
            index = node.node_set.index(node) + 1
            node.node_set.insert(index, dup_sibling)
          else
            node.after(sibling)
          end
        end

        def remove(node)
          # Special handling for declarations on Oga documents
          if node.is_a?(::Oga::XML::XmlDeclaration) &&
              node.parent.is_a?(::Oga::XML::Document)
            # Clear declaration state in attachment map
            attachments.set(node.parent, :xml_declaration, nil)
          end

          node.remove
        end

        def replace(node, new_node)
          node.replace(new_node)
        end

        def replace_children(node, new_children)
          node.children = []
          new_children.each { |child| add_child(node, child) }
        end

        def text_content(node)
          node.text
        end

        def inner_text(node)
          if node.is_a?(::Oga::XML::Element)
            node.inner_text
          else
            node.text
          end
        end

        def set_text_content(node, content)
          processed = preprocess_entities(content)
          if node.is_a?(::Oga::XML::Element)
            node.inner_text = processed
          else
            node.text = processed
          end
        end

        def cdata_content(node)
          node.text
        end

        def set_cdata_content(node, content)
          node.text = content
        end

        def comment_content(node)
          node.text
        end

        def set_comment_content(node, content)
          node.text = content
        end

        def processing_instruction_content(node)
          node.text
        end

        def set_processing_instruction_content(node, content)
          node.text = content
        end

        def namespace_prefix(namespace)
          # nil for the default namespace
          return if namespace.name == ::Oga::XML::Element::XMLNS_PREFIX

          namespace.name
        end

        def namespace_uri(namespace)
          namespace.uri
        end

        def namespace_definitions(node)
          return [] unless node.is_a?(::Oga::XML::Element)

          node.namespaces.values
        end

        # Doctype accessor methods
        # Note: Oga stores SYSTEM identifier in public_id for SYSTEM doctypes.
        # See: Oga::XML::Doctype puts SYSTEM dtd in public_id, system_id is nil.
        def doctype_name(native)
          native.name
        end

        def doctype_external_id(native)
          if native.type == "SYSTEM"
            nil
          else
            native.public_id
          end
        end

        def doctype_system_id(native)
          if native.type == "SYSTEM"
            native.public_id
          else
            native.system_id
          end
        end

        def xpath(node, expression, namespaces = nil)
          node.xpath(expression, {},
                     namespaces: namespaces&.transform_keys(&:to_s)).to_a
        rescue ::LL::ParserError => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "Oga",
            node: node,
          )
        end

        def at_xpath(node, expression, namespaces = nil)
          node.at_xpath(expression, namespaces: namespaces)
        rescue ::Oga::XPath::Error => e
          raise Moxml::XPathError.new(
            e.message,
            expression: expression,
            adapter: "Oga",
            node: node,
          )
        end

        def serialize(node, options = {})
          serialize_without_entity_processing(node, options)
        end

        def has_declaration?(native_doc, _wrapper)
          decl = attachments.get(native_doc, :xml_declaration)
          if decl.nil? && !attachments.key?(native_doc, :xml_declaration)
            native_doc.is_a?(::Oga::XML::Document) && !native_doc.xml_declaration.nil?
          else
            !decl.nil?
          end
        end

        def remove_declaration(native_doc)
          attachments.set(native_doc, :xml_declaration, nil)
        end

        private

        def declaration_to_xml(decl)
          parts = ["<?xml"]
          parts << %( version="#{decl.version}") if decl.version
          parts << %( encoding="#{decl.encoding}") if decl.encoding
          parts << %( standalone="#{decl.standalone}") if decl.standalone
          "#{parts.join}?>"
        end

        def serialize_without_entity_processing(node, options = {})
          if node.is_a?(::Oga::XML::Document)
            effective_xml_declaration = attachments.get(node, :xml_declaration)

            should_include_decl = if options.key?(:no_declaration)
                                    !options[:no_declaration]
                                  elsif options.key?(:declaration)
                                    options[:declaration]
                                  else
                                    effective_xml_declaration || node.xml_declaration ? true : false
                                  end

            output = []

            if should_include_decl
              decl = effective_xml_declaration || node.xml_declaration
              output << if decl
                          declaration_to_xml(decl)
                        else
                          '<?xml version="1.0" encoding="UTF-8"?>'
                        end
              output << "\n"
            end

            if node.doctype
              output << node.doctype.to_xml
              output << "\n"
            end

            node.children.each do |child|
              next if child.is_a?(::Oga::XML::XmlDeclaration)

              output << ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(child).to_xml
            end

            return output.join
          end

          ::Moxml::Adapter::CustomizedOga::XmlGenerator.new(node).to_xml
        end
      end
    end

    # Bridge between Oga SAX and Moxml SAX
    #
    # Translates Oga SAX events to Moxml::SAX::Handler events.
    # Oga has different event naming and namespace as first param.
    #
    # @private
    class OgaSAXBridge
      include Moxml::SAX::NamespaceSplitter

      def initialize(handler, marker = nil)
        @handler = handler
        @marker = marker
      end

      # Oga: on_element(namespace, name, attributes)
      # namespace may be nil
      # attributes is an array of [name, value] pairs
      def on_element(namespace, name, attributes)
        element_name = namespace ? "#{namespace}:#{name}" : name
        # Oga delivers attributes as array of [name, value] pairs.
        # Restore the &amp; sentinel we inserted before parsing so SAX
        # output matches DOM-decoded values.
        decoded = attributes.map { |a| [a[0].to_s, restore_amp(a[1])] }
        attr_hash, ns_hash = split_attributes_and_namespaces(decoded)
        @handler.on_start_element(element_name, attr_hash, ns_hash)
      end

      # Oga: after_element(namespace, name)
      def after_element(namespace, name)
        element_name = namespace ? "#{namespace}:#{name}" : name
        @handler.on_end_element(element_name)
      end

      def restore_amp(value)
        return value if @marker.nil?
        return value unless value.is_a?(String) && value.include?(@marker)

        value.gsub(@marker, "&")
      end

      def on_text(text)
        @handler.on_characters(restore_amp(text))
      end

      def on_cdata(text)
        @handler.on_cdata(restore_amp(text))
      end

      def on_comment(text)
        @handler.on_comment(text)
      end

      def on_processing_instruction(name, text)
        @handler.on_processing_instruction(name, text || "")
      end
    end
  end
end
