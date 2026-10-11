# frozen_string_literal: true

module Moxml
  # An HTML fragment (issue #353): the parsed top-level nodes of a
  # WHATWG fragment parse with a context element (body by default).
  # Not a Node — no parent, no document of its own; the adapter's
  # native fragment owns the parsed tree's lifetime.
  class HtmlFragment
    include Enumerable

    def initialize(native_fragment, context)
      @native_fragment = native_fragment
      @context = context
    end

    # The top-level nodes, moxml-wrapped, in tree order.
    def children
      children_natives.map { |n| Node.wrap(n, @context) }
    end

    def each(&block)
      children.each(&block)
    end

    def size
      children_natives.size
    end

    def empty?
      children_natives.empty?
    end

    def to_html(_options = {})
      @context.config.adapter.serialize_fragment(@native_fragment)
    end

    private

    def children_natives
      @context.config.adapter.fragment_children(@native_fragment)
    end
  end
end
