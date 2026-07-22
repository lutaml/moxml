# frozen_string_literal: true

module Moxml
  module Signature
    module C14n
      # Exclusive XML Canonicalization 1.0 (https://www.w3.org/TR/xml-exc-c14n/)
      #
      # Renders only the namespaces visibly utilized by each element's
      # qualified name and attributes (plus any in the inclusive prefix
      # list), as opposed to inclusive C14N which renders every in-scope
      # namespace on every element.
      #
      # Output is UTF-8 octets with no BOM.
      class Exclusive
        # `node`: a Moxml::Node — element, document, text, comment, or PI.
        # `with_comments:`: include comment nodes in output.
        # `inclusive_namespaces`: list of prefixes to always include even if
        #   not visibly utilized (InclusiveNamespacesPrefixList parameter).
        def canonicalize(node, with_comments: false, inclusive_namespaces: [])
          writer = Writer.new
          context = NamespaceContext.new
          render(node, writer, context, with_comments, inclusive_namespaces)
          writer.output
        end

        private

        def render(node, writer, context, with_comments, inclusive)
          case node_type(node)
          when :document
            node.children.each { |c| render(c, writer, context, with_comments, inclusive) }
          when :element
            render_element(node, writer, context, with_comments, inclusive)
          when :text, :cdata
            writer.text(node.content)
          when :comment
            writer.comment(node.content) if with_comments
          when :processing_instruction
            target, content = pi_target_and_content(node)
            writer.processing_instruction(target, content)
          end
        end

        def render_element(element, writer, context, with_comments, inclusive)
          bindings = bindings_on(element)
          context.push(bindings)

          prefix = element_namespace_prefix(element)
          local = element_name(element)

          visible_prefixes = visibly_used_prefixes(element, prefix)
          inclusive.each { |p| visible_prefixes.add(p) }
          visible_prefixes.add("xml") if visibly_uses_xml(element)

          namespaces_to_render = visible_prefixes.map do |p|
            uri = context.uri_for(p)
            [p, uri]
          end

          writer.open_tag(prefix, local)
          render_namespaces(writer, namespaces_to_render)
          render_attributes(writer, element)
          writer.close_tag_open

          element.children.each { |c| render(c, writer, context, with_comments, inclusive) }

          writer.close_tag(prefix, local)
          context.pop
        end

        def render_namespaces(writer, namespaces)
          sorted = namespaces.sort_by { |prefix, _| prefix.to_s }
          sorted.each { |prefix, uri| writer.namespace(prefix, uri) if uri }
        end

        def render_attributes(writer, element)
          attrs = collect_attributes(element)
          sorted = attrs.sort_by { |a| [a[:ns_uri] || "", a[:local]] }
          sorted.each { |a| writer.attribute(a[:expanded], a[:value]) }
        end

        def collect_attributes(element)
          attrs = []
          element.attributes.each do |attr|
            ns = attr.namespace
            attrs << {
              ns_uri: ns&.uri,
              ns_prefix: ns&.prefix,
              local: attr.name,
              expanded: attr_expanded_name(attr),
              value: attr.value,
            }
          end
          attrs
        end

        def attr_expanded_name(attr)
          ns = attr.namespace
          prefix = ns&.prefix
          if prefix && !prefix.empty?
            "#{prefix}:#{attr.name}"
          else
            attr.name
          end
        end

        def visibly_used_prefixes(element, element_prefix)
          set = Set.new
          set.add(element_prefix) if element_prefix && !element_prefix.empty?
          element.attributes.each do |attr|
            ns = attr.namespace
            p = ns&.prefix
            set.add(p) if p && !p.empty?
          end
          set
        end

        def visibly_uses_xml(element)
          element.attributes.any? { |a| a.namespace&.prefix == "xml" }
        end

        def bindings_on(element)
          bindings = {}
          element.namespaces.each do |ns|
            prefix = ns.prefix
            prefix = "" if prefix.nil? || prefix == "xmlns"
            bindings[prefix] = ns.uri
          end
          bindings
        end

        def element_namespace_prefix(element)
          ns = element.namespace
          ns&.prefix
        end

        def element_name(element)
          element.name
        end

        def pi_target_and_content(node)
          [node.name, node.text]
        end

        def node_type(node)
          return :document if node.is_a?(::Moxml::Document)
          return :element if node.is_a?(::Moxml::Element)
          return :text if node.is_a?(::Moxml::Text)
          return :cdata if node.is_a?(::Moxml::Cdata)
          return :comment if node.is_a?(::Moxml::Comment)
          if node.is_a?(::Moxml::ProcessingInstruction)
            return :processing_instruction
          end

          :unknown
        end
      end
    end
  end
end
