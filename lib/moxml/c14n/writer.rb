# frozen_string_literal: true

module Moxml
  module C14n
    # Builds canonical octet output incrementally.
    # Output is always UTF-8 with no BOM.
    class Writer
      attr_reader :output

      def initialize
        @output = (+"")
        # Tracks namespaces already rendered in the output ancestor chain,
        # so descendants don't re-render the same declaration.
        # Key: element (by object identity), value: { prefix => uri }.
        @rendered_stack = []
      end

      def <<(str)
        @output << str
        self
      end

      def raw(str)
        @output << str.to_s
        self
      end

      # Push a fresh "rendered" frame for the given element. Called by the
      # canonicalizer before rendering the element's namespaces.
      def open_rendered_frame(element)
        parent_rendered = @rendered_stack.last || {}
        # Inherit parent's rendered namespaces as the starting set.
        @rendered_stack.push(parent_rendered.dup)
        element
      end

      def close_rendered_frame
        @rendered_stack.pop
        self
      end

      def rendered_namespaces_for(_element)
        @rendered_stack.last || {}
      end

      def mark_rendered(_element, prefix, uri)
        (@rendered_stack.last || {})[prefix] = uri
        self
      end

      def open_tag(prefix, local)
        @output << "<"
        @output << "#{prefix}:" unless prefix.nil? || prefix.empty?
        @output << local
        self
      end

      def close_tag_open
        @output << ">"
        self
      end

      def close_tag_self_close
        @output << "></"
        self
      end

      def close_tag(prefix, local)
        @output << "</"
        @output << "#{prefix}:" unless prefix.nil? || prefix.empty?
        @output << local
        @output << ">"
        self
      end

      def attribute(expanded_name, value)
        @output << " "
        @output << expanded_name
        @output << "=\""
        @output << C14n.escape_attribute(value)
        @output << "\""
        self
      end

      def namespace(prefix, uri)
        @output << " "
        if prefix.nil? || prefix.empty?
          @output << "xmlns"
        else
          @output << "xmlns:"
          @output << prefix
        end
        @output << "=\""
        @output << C14n.escape_attribute(uri)
        @output << "\""
        self
      end

      def text(content)
        @output << C14n.escape_text(content)
        self
      end

      def comment(content)
        @output << "<!--"
        @output << C14n.escape_text(content)
        @output << "-->"
        self
      end

      def processing_instruction(target, content)
        @output << "<?"
        @output << target
        @output << " "
        @output << content
        @output << "?>"
        self
      end
    end
  end
end
