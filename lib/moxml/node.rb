# frozen_string_literal: true

module Moxml
  class Node
    include XmlUtils
    include Enumerable

    TYPES = %i[
      element text cdata comment processing_instruction document
      declaration doctype namespace attribute unknown entity_reference
    ].freeze

    attr_reader :native, :context

    def initialize(native, context)
      @context = context
      @native = native
      @parent_node = nil
    end

    # Update native reference after identity-changing operations
    # (e.g., LibXML doc.root= creates a new Ruby wrapper)
    def refresh_native!(new_native)
      unless new_native.equal?(@native)
        context.unregister_wrapper(@native)
        @native = new_native
        context.register_wrapper(new_native, self)
        clear_native_memo!
      end
      self
    end

    # Wrapper-local memos derived from the native (name, attribute
    # reads) die with the native they were computed from.
    def clear_native_memo!
      @name = nil
      @attribute_cache = nil
    end

    def document
      Document.wrap(adapter.document(@native), context)
    end

    def parent
      Moxml::Node.wrap(adapter.parent(@native), context)
    end

    def children
      @children ||= begin
        natives = adapter.children(@native)
        natives = natives.map { adapter.patch_node(_1, @native) } if adapter.patches_children?
        NodeSet.new(natives, context, self)
      end
    end

    def next_sibling
      Moxml::Node.wrap(adapter.next_sibling(@native), context)
    end

    def previous_sibling
      Moxml::Node.wrap(adapter.previous_sibling(@native), context)
    end

    def add_child(node)
      node = prepare_node(node)
      adapter.add_child(@native, node.native)
      # Refresh native in case adapter changed identity (e.g., LibXML doc.root=)
      refreshed = adapter.actual_native(node.native, @native)
      node.refresh_native!(refreshed) if refreshed && refreshed != node.native
      node.parent_node = self
      # The adopted subtree's in-scope namespaces changed
      node.invalidate_namespace_cache!
      invalidate_children_cache!
      self
    end

    def add_previous_sibling(node)
      node = prepare_node(node)
      adapter.add_previous_sibling(@native, node.native)
      invalidate_parent_children_cache!
      self
    end

    def add_next_sibling(node)
      node = prepare_node(node)
      adapter.add_next_sibling(@native, node.native)
      invalidate_parent_children_cache!
      self
    end

    def remove
      invalidate_parent_children_cache!
      adapter.remove(@native)
      invalidate_children_cache!
      # The detached subtree left its declaring ancestors behind
      invalidate_namespace_cache!
      self
    end

    # Namespace-scope caches live on Element; the base no-op lets tree
    # mutations invalidate uniformly without type checks.
    def invalidate_namespace_cache!; end

    def replace(node)
      node = prepare_node(node)
      invalidate_parent_children_cache!
      adapter.replace(@native, node.native)
      invalidate_children_cache!
      self
    end

    def to_xml(options = {})
      # Determine if we should include XML declaration
      # For Document nodes: check native then wrapper, unless explicitly overridden
      # For other nodes: default to no declaration unless explicitly set
      serialize_options = default_options.merge(options)
      serialize_options[:no_declaration] = !should_include_declaration?(options)

      result = adapter.serialize(@native, serialize_options)
      result = apply_line_ending(result, serialize_options[:line_ending])

      # Restore entity markers to named entity references; skipped
      # when the adapter knows the document carries no markers.
      result = adapter.restore_entities(result) if adapter.entity_bearing?(@native)
      result
    end

    def xpath(expression, namespaces = {})
      result = adapter.xpath(@native, expression, namespaces)
      # Adapter contract: Array<native> | LazyNodeSet | scalar.
      # Scalars (count(), string-length(), booleans) pass through
      # unwrapped; the set forms wrap lazily.
      result.is_a?(Array) || result.is_a?(LazyNodeSet) ? NodeSet.new(result, context) : result
    end

    # Flattened post-order records for this subtree without
    # allocating wrappers — see Moxml::Materializer (issue #132).
    # Returns an Enumerator when no block is given.
    def materialize(&block)
      Materializer.materialize(self, &block)
    end

    # Zero-allocation streaming form — flat reused buffers valid only
    # inside the block (issue #143). See Moxml::Materializer.
    def materialize_fields(&block)
      raise ArgumentError, "materialize_fields requires a block" unless block

      Materializer.materialize_fields(self, &block)
    end

    def at_xpath(expression, namespaces = {})
      Moxml::Node.wrap(adapter.at_xpath(@native, expression, namespaces),
                       context)
    end

    # Convenience find methods (aliases for xpath methods)
    def find(xpath_expression, namespaces = {})
      at_xpath(xpath_expression, namespaces)
    end

    def find_all(xpath_expression, namespaces = {})
      xpath(xpath_expression, namespaces).to_a
    end

    # Check if node has any children
    def has_children?
      !children.empty?
    end

    # Get first/last child
    def first_child
      children.first
    end

    def last_child
      children.last
    end

    # Returns the text content of this node
    # Subclasses should override this method
    # Element and Text have their own implementations
    def text
      ""
    end

    # Returns the content/value of this node as a string.
    # Each subclass overrides this with type-specific semantics:
    # - Text, Comment, Cdata: raw text content
    # - ProcessingInstruction: instruction content
    # - Attribute: attribute value
    # - Element: delegates to text (descendant text concatenation)
    def content
      ""
    end

    # Returns the namespace of this node
    # Only applicable to Element nodes, returns nil for others
    def namespace
      return nil unless element?

      ns = adapter.namespace(@native)
      ns && Namespace.new(ns, context)
    end

    # Returns all namespace definitions on this node
    # Only applicable to Element nodes, returns empty array for others
    def namespaces
      return [] unless element?

      adapter.namespace_definitions(@native).map do |ns|
        Namespace.new(ns, context)
      end
    end

    # Recursively yield all descendant nodes
    # Used by XPath descendant-or-self and descendant axes
    def each_node(&block)
      children.each do |child|
        yield child
        child.each_node(&block)
      end
    end

    # Yield direct children, enabling Enumerable on the node.
    def each(&block)
      return to_enum(:each) unless block

      children.each(&block)
    end

    # Returns all ancestor nodes from the parent up to and including
    # the document node.
    #
    # @return [NodeSet] ancestors ordered nearest-first
    def ancestors
      return NodeSet.new([], context) if document?

      natives = []
      current = parent
      while current
        natives << current.native
        break if current.document?

        current = current.parent
      end
      NodeSet.new(natives, context)
    end

    # Returns all descendant nodes (children, grandchildren, and so on),
    # excluding the node itself.
    #
    # @return [NodeSet] descendants in document order
    def descendants
      natives = []
      each_node { |node| natives << node.native }
      NodeSet.new(natives, context)
    end

    # Returns the siblings after this node, in document order.
    #
    # @return [NodeSet]
    def following_siblings
      parent = self.parent
      return NodeSet.new([], context) unless parent

      siblings = parent.children.to_a
      index = siblings.index { |child| child.native.equal?(@native) }
      return NodeSet.new([], context) if index.nil?

      NodeSet.new(siblings[(index + 1)..].map(&:native), context)
    end

    # Returns the siblings before this node, in document order.
    #
    # @return [NodeSet]
    def preceding_siblings
      parent = self.parent
      return NodeSet.new([], context) unless parent

      siblings = parent.children.to_a
      index = siblings.index { |child| child.native.equal?(@native) }
      return NodeSet.new([], context) if index.nil?

      NodeSet.new(siblings[0...index].map(&:native), context)
    end

    # Deep copy of the node (both dup and clone create deep copies for XML nodes)
    def dup
      Moxml::Node.wrap(adapter.duplicate_node(@native), context)
    end

    alias clone dup

    # Returns an XPath expression that uniquely locates this node within
    # its document. Positional predicates are emitted only when sibling
    # elements share the same qualified name, keeping paths minimal.
    #
    # @return [String] XPath expression
    # @raise [Moxml::NotImplementedError] for node types other than
    #   element and document
    def path
      return "/" if document?

      unless element?
        raise Moxml::NotImplementedError.new(
          "path is only supported for element and document nodes",
          feature: "path",
        )
      end

      segments = []
      current = self
      while current && !current.document?
        segments.unshift(path_segment_for(current))
        current = current.parent
      end
      "/#{segments.join('/')}"
    end

    # Returns the 1-based line number where this node appears in the
    # source XML, or nil when the underlying adapter does not track
    # source positions.
    #
    # @return [Integer, nil]
    def line_number
      adapter.line_number(@native)
    end

    def outer_xml
      to_xml
    end

    def before(node)
      add_previous_sibling(node)
    end

    def after(node)
      add_next_sibling(node)
    end

    def blank?
      text.strip.empty?
    end

    def ==(other)
      self.class == other.class && @native == other.native
    end

    TYPES.each do |node_type|
      define_method "#{node_type}?" do
        node_type_cached == node_type
      end
    end

    # The adapter's type probe is an FFI call per invocation; the
    # type is fixed for a node's lifetime, so the first answer is
    # memoized on the wrapper.
    def node_type_cached
      @node_type_cached ||= adapter.node_type(@native)
    end
    private :node_type_cached

    # Returns the primary identifier for this node type
    # For Element: the tag name
    # For Attribute: the attribute name
    # For ProcessingInstruction: the target
    # For content nodes (Text, Comment, Cdata, Declaration): nil (no identifier)
    # For Doctype: nil (not fully implemented across adapters)
    #
    # @return [String, nil] the node's primary identifier or nil
    def identifier
      nil
    end

    # Registry mapping node type symbols to wrapper classes.
    # Built lazily to avoid load-order issues with subclasses.
    def self.node_type_map
      @node_type_map ||= {
        element: Element,
        text: Text,
        cdata: Cdata,
        comment: Comment,
        processing_instruction: ProcessingInstruction,
        document: Document,
        declaration: Declaration,
        doctype: Doctype,
        attribute: Attribute,
        entity_reference: EntityReference,
      }.freeze
    end

    def self.wrap(node, context)
      return nil if node.nil?

      cached = context.wrapper_for(node)
      return cached if cached

      type = adapter(context).node_type(node)
      klass = node_type_map[type] || self

      klass.new(node, context).tap { |wrapper| context.register_wrapper(node, wrapper) }
    end

    # Internal: Set the parent node for cache invalidation tracking.
    # Called by NodeSet, Document, Element when establishing parent-child
    # relationships. Public to allow cross-class usage within Moxml internals.
    attr_writer :parent_node

    protected

    def adapter
      # A context's adapter object is fixed for its lifetime; the
      # chain deref ran on every node access.
      @adapter ||= context.config.adapter
    end

    def self.adapter(context)
      context.config.adapter
    end

    # Invalidate cached children. Called by mutation methods
    # and by Element attribute/namespace caches.
    def invalidate_children_cache!
      @children = nil
    end

    # Invalidate parent's cached children when this node
    # is removed/replaced from its parent's child list.
    def invalidate_parent_children_cache!
      @parent_node&.invalidate_children_cache!
    end

    private

    # XPath segment for an element: the qualified name, plus a positional
    # predicate only when same-named element siblings make it ambiguous.
    def path_segment_for(element)
      name = element.name
      parent = element.parent
      return name unless parent

      same_name = parent.children.select do |child|
        child.element? && child.name == name
      end
      return name if same_name.size == 1

      "#{name}[#{same_name.find_index(element) + 1}]"
    end

    def prepare_node(node)
      case node
      when String then Text.new(adapter.create_text(node), context)
      when Node then node
      else
        raise Moxml::DocumentStructureError.new(
          "Invalid node type: #{node.class}. Expected String or Moxml::Node",
          operation: "prepare_node",
          state: "node_type: #{node.class}",
        )
      end
    end

    def default_options
      {
        encoding: context.config.default_encoding,
        indent: context.config.default_indent,
        line_ending: context.config.default_line_ending,
        # The short format of empty tags in Oga and Nokogiri isn't configurable
        # Oga: <empty /> (with a space)
        # Nokogiri: <empty/> (without a space)
        # The expanded format is enforced to avoid this conflict
        expand_empty: true,
      }
    end

    def should_include_declaration?(options)
      return options[:declaration] if options.key?(:declaration)
      return options.fetch(:declaration, false) unless is_a?(Document)

      # For Document nodes, delegate to adapter for native state check
      adapter.has_declaration?(@native, self)
    end

    def apply_line_ending(xml, line_ending)
      return xml if line_ending == Config::LINE_ENDING_LF || !xml.include?("\n")

      xml.gsub(/\r?\n/, line_ending)
    end
  end
end
