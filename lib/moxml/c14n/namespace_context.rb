# frozen_string_literal: true

module Moxml
  module C14n
    # Tracks in-scope namespace URIs along the ancestor chain of the
    # element currently being canonicalized. The canonicalizer pushes
    # when entering an element and pops when leaving.
    #
    # `xml` prefix is always bound to the XML namespace per XML 1.0 spec.
    class NamespaceContext
      DEFAULT_XML_BINDING = { "xml" => C14n::XML_URI }.freeze

      attr_reader :bindings

      def initialize(initial = {})
        @stack = []
        @bindings = DEFAULT_XML_BINDING.dup
        merge(initial)
      end

      def push(bindings_to_apply)
        applied = {}
        bindings_to_apply.each do |prefix, uri|
          prev = @bindings[prefix]
          applied[prefix] = prev
          @bindings[prefix] = uri
        end
        @stack.push(applied)
        self
      end

      def pop
        applied = @stack.pop
        applied.each do |prefix, prev|
          if prev.nil?
            @bindings.delete(prefix)
            @bindings[prefix] = C14n::XML_URI if prefix == "xml"
          else
            @bindings[prefix] = prev
          end
        end
        self
      end

      def uri_for(prefix)
        @bindings[prefix]
      end

      def binding_for(prefix)
        @bindings[prefix]
      end

      def include?(prefix)
        @bindings.key?(prefix)
      end

      def to_h
        @bindings.dup
      end

      private

      def merge(hash)
        hash.each { |prefix, uri| @bindings[prefix] = uri }
      end
    end
  end
end
