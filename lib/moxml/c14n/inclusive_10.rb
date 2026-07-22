# frozen_string_literal: true

module Moxml
  module C14n
    # Inclusive Canonical XML 1.0 (https://www.w3.org/TR/xml-c14n/)
    #
    # Unlike exclusive C14N, inclusive C14N "attracts" ancestor context:
    # at the apex element, ALL in-scope namespaces are rendered, including
    # those inherited from ancestors outside the canonicalization subset.
    #
    # xml:* inheritable attributes (xml:lang, xml:space) are also inherited
    # from the nearest ancestor in which they are declared.
    class Inclusive10
      # `node`: a Moxml::Node — element, document, text, comment, or PI.
      # `with_comments:`: include comment nodes in output.
      # `inclusive_namespaces`: extra prefixes to render at the apex
      #   (informational; ignored in pure inclusive C14N, which already
      #   renders all in-scope namespaces).
      # rubocop:disable Lint/UnusedMethodArgument -- signature must match CanonicalizationBase
      def canonicalize(node, with_comments: false, inclusive_namespaces: [])
        # rubocop:enable Lint/UnusedMethodArgument
        writer = Writer.new
        context = NamespaceContext.new
        render(node, writer, context, with_comments, true)
        writer.output
      end

      private

      def render(node, writer, context, with_comments, is_apex)
        case node_type(node)
        when :document
          node.children.each do |c|
            render(c, writer, context, with_comments, is_apex)
            is_apex = false
          end
        when :element
          render_element(node, writer, context, with_comments, is_apex)
        when :text, :cdata
          writer.text(node.content)
        when :comment
          writer.comment(node.content) if with_comments
        when :processing_instruction
          target, content = pi_target_and_content(node)
          writer.processing_instruction(target, content)
        end
      end

      def render_element(element, writer, context, with_comments, is_apex)
        declared = bindings_declared_on(element)
        context.push(declared)

        in_scope_bindings = if is_apex
                              bindings_in_scope_on(element)
                            else
                              declared
                            end

        namespaces_to_render = renderable_namespaces(
          element, in_scope_bindings, writer, is_apex
        )

        prefix = element_namespace_prefix(element)
        local = element_name(element)

        writer.open_rendered_frame(element)
        writer.open_tag(prefix, local)
        render_namespaces(writer, element, namespaces_to_render)
        render_attributes(writer, element)
        writer.close_tag_open

        element.children.each { |c| render(c, writer, context, with_comments, false) }

        writer.close_tag(prefix, local)
        writer.close_rendered_frame
        context.pop
      end

      def renderable_namespaces(element, in_scope_bindings, writer, is_apex)
        already_rendered = writer.rendered_namespaces_for(element)
        if is_apex
          in_scope_bindings.filter_map do |prefix, uri|
            next if prefix == "xml" && already_rendered[prefix] == uri

            [prefix, uri]
          end
        else
          in_scope_bindings.filter_map do |prefix, uri|
            next if already_rendered[prefix] == uri

            [prefix, uri]
          end
        end
      end

      def render_namespaces(writer, element, namespaces)
        sorted = namespaces.sort_by { |(prefix, _)| prefix.to_s }
        sorted.each do |(prefix, uri)|
          writer.namespace(prefix, uri)
          writer.mark_rendered(element, prefix, uri)
        end
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
            local: attr.name,
            expanded: attr_expanded_name(attr),
            value: attr.value,
          }
        end
        attrs
      end

      def attr_expanded_name(attr)
        prefix = attr.namespace&.prefix
        if prefix && !prefix.empty?
          "#{prefix}:#{attr.name}"
        else
          attr.name
        end
      end

      def bindings_declared_on(element)
        bindings = {}
        element.namespaces.each do |ns|
          prefix = ns.prefix
          prefix = "" if prefix.nil? || prefix == "xmlns"
          bindings[prefix] = ns.uri
        end
        bindings
      end

      def bindings_in_scope_on(element)
        bindings = {}
        element.in_scope_namespaces.each do |ns|
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
        return :processing_instruction if node.is_a?(::Moxml::ProcessingInstruction)

        :unknown
      end
    end
  end
end
