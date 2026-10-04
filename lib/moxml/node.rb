# frozen_string_literal: true

module Moxml
  # Instance behavior for Moxml::Node, extracted so the leptris
  # adapter can extend natives with it in place (issue #230); the
  # class remains the consumer-facing contract and the wrap factory.
  module NodeBehavior
    include XmlUtils
    include Enumerable

    TYPES = %i[
      element text cdata comment processing_instruction document
      declaration doctype namespace attribute unknown entity_reference
    ].freeze

    attr_reader :native, :context

    # adapter/node_type are primed by Node.wrap, which resolves both
    # before choosing the wrapper class — a fresh wrapper would
    # otherwise pay the context hop and the type probe again on its
    # first access.
    def initialize(native, context, adapter = nil, node_type = nil)
      prime_contract(native, context, adapter, node_type)
    end

    # Update native reference after identity-changing operations
    # (e.g., LibXML doc.root= creates a new Ruby wrapper)
    # Contract priming shared by the constructor and the extend-in-place
    # mint (#230): an extended native IS its own @native.
    def prime_contract(native, context, adapter = nil, node_type = nil)
      @context = context
      @native = native
      @parent_node = nil
      @adapter = adapter
      @node_type_cached = node_type
      self
    end

    def refresh_native!(new_native)
      unless new_native.equal?(@native)
        # Cache-stable binding nodes carry the wrapper in an ivar
        # (see Node.wrap_with) — re-point it there; other natives
        # ride the context map.
        if @native.instance_variable_defined?(:@moxml_wrapper)
          @native.instance_variable_set(:@moxml_wrapper, nil)
        else
          context.unregister_wrapper(@native)
        end
        @native = new_native
        if new_native.instance_variable_defined?(:@c_address)
          new_native.instance_variable_set(:@moxml_wrapper, self)
        else
          context.register_wrapper(new_native, self)
        end
        clear_native_memo!
      end
      self
    end

    # Wrapper-local memos derived from the native (name, attribute
    # reads) die with the native they were computed from.
    def clear_native_memo!
      @name = nil
      @attribute_cache = nil
      @entity_bearing_gen = nil
    end

    def document
      Moxml::Node.wrap(adapter.document(@native), context)
    end

    def parent
      Moxml::Node.wrap(adapter.parent(@native), context)
    end

    def children
      # Generation-checked memo: mutations bump the context counter, so
      # this self-invalidates even when the same logical node is served
      # by multiple wrapper representations (native vs binding duality).
      @children = nil if @children_gen != context.children_generation
      @children_gen = context.children_generation
      @children ||= begin
        # The wrapper's entity memo decides the marker split; the
        # adapter would otherwise re-derive it per call (a C parent
        # climb on the native layer). The kwarg rides along only
        # for adapters that accept it — downstream overrides with
        # the pre-0.5.36 one-argument signature raise ArgumentError
        # otherwise (issue #218).
        natives = if adapter.children_accepts_entity_flag?
                    adapter.children(@native, entity_bearing: entity_bearing?)
                  else
                    adapter.children(@native)
                  end
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

    # Nokogiri-compatible reader spellings.
    alias next next_sibling
    alias previous previous_sibling

    # Nokogiri-compatible: nearest sibling elements, skipping text and
    # comment nodes.
    def next_element
      s = next_sibling
      s = s.next_sibling while s && !s.is_a?(Moxml::Element)
      s
    end

    def previous_element
      s = previous_sibling
      s = s.previous_sibling while s && !s.is_a?(Moxml::Element)
      s
    end

    # Nokogiri-compatible append sugar: node << appends. Strings
    # parse as fragments (markup, not literal text).
    def <<(node)
      add_child(node)
      self
    end

    # Nokogiri-compatible: reparent — node.parent = new_parent moves
    # this node (removing it from its current tree) under the target.
    def parent=(new_parent)
      remove
      new_parent.add_child(self)
    end

    # Insert ahead of the current first child (nokogiri-monkeypatch
    # convention used across metanorma). Strings parse as fragments
    # (the sibling_operand convention).
    def add_first_child(node)
      if first_child
        first_child.add_previous_sibling(node)
      else
        add_child(node)
      end
      self
    end

    def add_child(node)
      # Nokogiri semantics: a String operand is MARKUP, parsed and
      # appended (cleanup code inserts "<bibliography/>" style
      # strings); the adapter path would mint a literal text node.
      # Metanorma's Nokogiri returns the new children as a NodeSet
      # for markup (misc.add_child("<UnitsML/>").first idiom), self
      # for nodes.
      if node.is_a?(String)
        nodes = context.parse_fragment(node).to_a
        nodes.each { |child| attach_child(child) }
        return NodeSet.new(nodes.map(&:native), context)
      end
      # Nokogiri semantics: appending a NodeSet appends each node
      return add_child_nodeset(node) if node.is_a?(NodeSet)

      attach_child(node)
      self
    end

    def add_previous_sibling(node)
      # String operands insert every fragment root; returns the new
      # nodes as a NodeSet (metanorma idiom: sect.add_next_sibling(
      # "<bibliography/>").first).
      if node.is_a?(String)
        nodes = context.parse_fragment(node).to_a
        nodes.each { |n| attach_previous_sibling(n) }
        return NodeSet.new(nodes.map(&:native), context)
      end
      return insert_nodeset(node) { |n| attach_previous_sibling(n) } if node.is_a?(NodeSet)

      attach_previous_sibling(node)
      self
    end

    # Nokogiri-compatible assignment forms: node.next = / node.previous =.
    # String operands are parsed as XML fragments, like Nokogiri.
    def next=(node)
      add_next_sibling(node)
    end

    def previous=(node)
      add_previous_sibling(node)
    end

    def add_next_sibling(node)
      if node.is_a?(String)
        nodes = context.parse_fragment(node).to_a
        anchor = self
        nodes.each do |n|
          attach_next_sibling_to(anchor, n)
          anchor = n
        end
        return NodeSet.new(nodes.map(&:native), context)
      end
      attach_next_sibling_to(self, node)
      self
    end

    def attach_child(node)
      context.bump_children_generation
      node = prepare_node(node)
      adapter.add_child(@native, node.native)
      # Refresh native in case adapter changed identity (e.g., LibXML
      # doc.root=); stable-identity adapters skip the round trip.
      unless adapter.native_identity_stable?
        refreshed = adapter.actual_native(node.native, @native)
        node.refresh_native!(refreshed) if refreshed && refreshed != node.native
      end
      node.parent_node = self
      # The adopted subtree's in-scope namespaces changed
      node.invalidate_namespace_cache!
      invalidate_children_cache!
      self
    end

    def attach_previous_sibling(node)
      context.bump_children_generation
      node = prepare_node(node)
      adapter.add_previous_sibling(@native, node.native)
      # Invalidate the parent's memoized children list. The wrapper-side
      # @parent_node link is only set when this node was yielded through a
      # parent-aware NodeSet; nodes obtained via at()/xpath() carry no such
      # link, so resolve the parent wrapper from the adapter instead.
      parent&.invalidate_children_cache!
      invalidate_parent_children_cache!
      self
    end

    def attach_next_sibling_to(anchor, node)
      context.bump_children_generation
      node = prepare_node(node)
      adapter.add_next_sibling(anchor.native, node.native)
      anchor.parent&.invalidate_children_cache!
      anchor.invalidate_parent_children_cache!
      self
    end

    def remove
      # Nokogiri parity: unlinking an already-detached node is a
      # no-op returning self. Re-attach idioms like
      # `t << n.replace(x).remove` (standoc term cleanup) detach with
      # #replace and rely on this; leptris would raise "Not found".
      # The wrapper-side @parent_node link decides when present
      # (add_child sets it); the adapter resolution covers
      # link-less wrappers (at()-resolved nodes), whose parents are
      # canonical since #313.
      return self if @parent_node.nil? && parent.nil?

      context.bump_children_generation
      invalidate_parent_children_cache!
      adapter.remove(@native)
      # The wrapper-side parent link dies with the attach — leaving it
      # stale makes a later #remove's guard trust a parent that no
      # longer exists and push an already-detached node into the
      # engine (leptris: "Not found").
      @parent_node = nil
      invalidate_children_cache!
      # The detached subtree left its declaring ancestors behind
      invalidate_namespace_cache!
      self
    end

    # Namespace-scope caches live on Element; the base no-op lets tree
    # mutations invalidate uniformly without type checks.
    def invalidate_namespace_cache!; end

    def replace(node)
      context.bump_children_generation
      # Nokogiri semantics: replacing with a NodeSet replaces with its
      # nodes in order
      if node.is_a?(NodeSet)
        # each node lands immediately before self, after the
        # previously inserted one, so forward iteration preserves
        # order
        node.to_a.each { |n| add_previous_sibling(adopt(n)) }
        return remove
      end
      node = prepare_node(node)
      invalidate_parent_children_cache!
      adapter.replace(@native, node.native)
      # Self is detached by the replace — drop the stale parent link
      # (see #remove).
      @parent_node = nil
      invalidate_children_cache!
      self
    end

    def to_xml(options = {})
      # Determine if we should include XML declaration
      # For Document nodes: check native then wrapper, unless explicitly overridden
      # For other nodes: default to no declaration unless explicitly set
      serialize_options = if options.empty? && !is_a?(Document)
                            context.default_element_serialize_options
                          else
                            merged = context.default_serialize_options.merge(options)
                            merged[:no_declaration] = !should_include_declaration?(options)
                            merged
                          end

      result = adapter.serialize(@native, serialize_options)
      result = apply_line_ending(result, serialize_options[:line_ending])

      # Restore entity markers to named entity references; skipped
      # when the adapter knows the document carries no markers.
      result = adapter.restore_entities(result) if entity_bearing?
      result
    end

    # Nokogiri-compatible: string interpolation of a node serializes
    # it ("#{node}" in cleanup code), not Object#to_s.
    def to_s
      to_xml
    end

    # Nokogiri-compatible: to_str yields the text content (their C
    # node_to_str; standoc does x.content = x.to_str on <script>).
    def to_str
      text
    end

    # Memoized against the adapter's serialize generation — the
    # entity-marker flag flips at parse and entity-reference mint,
    # both adapter-level, and the generation bump is the invalidation
    # signal. Adapters with static answers (base class) never bump.
    # The adapter resolves the owning document itself (doc_for is a
    # single C read on the native layer); wrappers no longer climb.
    def entity_bearing?
      gen = adapter.serialize_generation
      if @entity_bearing_gen == gen
        @entity_bearing
      else
        @entity_bearing_gen = gen
        @entity_bearing = adapter.entity_bearing?(@native)
      end
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

    # Nokogiri-compatible sugar: at/search/at_css/css. Nokogiri's
    # at/search auto-detect XPath vs CSS; the XPath-first fallback
    # covers the dominant caller shape (XPath expression strings)
    # while css/at_css serve stylesheet-style selectors.
    def at(expression, namespaces = {})
      at_css_or_xpath(expression, namespaces)
    end

    def search(expression, namespaces = {})
      xpath(expression, namespaces)
    end

    def css(_expression)
      raise Moxml::NotImplementedError,
            "CSS selectors are not supported; use search with XPath"
    end

    def at_css(_expression)
      raise Moxml::NotImplementedError,
            "CSS selectors are not supported; use at with XPath"
    end

    def at_css_or_xpath(expression, namespaces = {})
      at_xpath(expression, namespaces)
    end

    # Nokogiri-compatible depth-first traversal: yields self, then
    # children recursively (document-order visitor).
    def traverse(&block)
      return to_enum(:traverse) unless block

      yield self
      children.each { |child| child.traverse(&block) }
      self
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
      ns && Wrappers::Namespace.new(ns, context)
    end

    # Returns all namespace definitions on this node
    # Only applicable to Element nodes, returns empty array for others
    def namespaces
      return [] unless element?

      adapter.namespace_definitions(@native).map do |ns|
        Wrappers::Namespace.new(ns, context)
      end
    end

    # Recursively yield all descendant nodes
    # Used by XPath descendant-or-self and descendant axes
    def each_node(&block)
      unless block
        # Eager materialization: the leptris C-side walk rb_yields
        # from the C callback and segfaults across fiber-suspended
        # enumerator frames, so the no-block form never enters it.
        nodes = []
        each_node { |node| nodes << node }
        return nodes.each
      end

      # Adapters with a C-side subtree walk take it in one
      # dispatch; the recursive children walk stays the fallback.
      return if adapter.walk_descendants(@native, context, &block)

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
    # Nokogiri-compatible: an element-name argument filters the set.
    def ancestors(selector = nil)
      all = _ancestors_all
      return all unless selector

      all.select { |a| a.name == selector.to_s }
    end

    def _ancestors_all
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
    def path
      return "/" if document?

      segments = []
      current = self
      while current && !current.document?
        segments.unshift(path_segment_for(current))
        current = current.parent
      end
      "/#{segments.join('/')}"
    end

    # The XPath node-test spelling for this non-element node.
    def path_type_test
      if text? || cdata?
        "text()"
      elsif comment?
        "comment()"
      elsif processing_instruction?
        "processing-instruction()"
      else
        name.to_s
      end
    end

    # Returns the 1-based line number where this node appears in the
    # source XML, or nil when the underlying adapter does not track
    # source positions.
    #
    # @return [Integer, nil]
    def line_number
      adapter.line_number(@native)
    end

    # {line, col_start, col_end} where the engine exposes source
    # positions (leptris 1.9.181+); nil elsewhere. Created nodes
    # answer zeros upstream — distinguishable from nil by callers
    # that care.
    def source_position
      adapter.source_position(@native)
    end

    # Content-defined Merkle digest of this subtree (issue #173,
    # companion to leptris#869): a u64 Integer where the backend
    # computes one, nil everywhere else. Consumers gate on nil and
    # fall back to walking. Equal digests imply subtree equivalence
    # under the flag set; unequal digests imply nothing (descend).
    # +drop_ws_text+ skips whitespace-only text nodes.
    #
    # @return [Integer, nil]
    def digest(drop_ws_text: false)
      adapter.digest(@native, drop_ws_text: drop_ws_text)
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
      # Native equality goes through the adapter: engines with a
      # native read layer hand out two wrapper classes over one C
      # node, and raw native == is false across that seam.
      other.is_a?(Moxml::Node) &&
        adapter.same_node?(@native, other.native)
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

    # Internal: Set the parent node for cache invalidation tracking.
    # Called by NodeSet, Document, Element when establishing parent-child
    # relationships. Public to allow cross-class usage within Moxml internals.
    attr_accessor :parent_node

    def adapter
      # A context's adapter object is fixed for its lifetime; the
      # chain deref ran on every node access.
      @adapter ||= context.config.adapter
    end

    protected

    def invalidate_children_cache!
      @children = nil
    end

    # Invalidate parent's cached children when this node
    # is removed/replaced from its parent's child list.
    def invalidate_parent_children_cache!
      @parent_node&.invalidate_children_cache!
    end

    private

    # XPath segment for a node: elements use their qualified name,
    # other node kinds their XPath type test (text(), comment(), ...).
    # A positional predicate is emitted only when same-kind siblings
    # make the segment ambiguous.
    def path_segment_for(node)
      name = node.element? ? node.name : node.path_type_test
      parent = node.parent
      return name unless parent

      same_kind = parent.children.select do |child|
        if node.element?
          child.element? && child.name == name
        else
          !child.element? && child.path_type_test == name
        end
      end
      return name if same_kind.size == 1

      "#{name}[#{same_kind.find_index(node) + 1}]"
    end

    # Nodes from another document must be adopted before attachment:
    # the leptris C layer faults on serializing cross-document
    # pointers. Re-parsing into this document is the adoption.
    def adopt(node)
      return node if node.document == document

      context.parse_fragment(node.to_xml).to_a.first || node
    end

    def add_child_nodeset(node_set)
      node_set.each { |n| attach_child(adopt(n)) }
      node_set
    end

    def insert_nodeset(node_set)
      node_set.each { |n| yield adopt(n) }
      node_set
    end

    def prepare_node(node)
      case node
      when String then Moxml::Node.wrap(adapter.create_text(node), context)
      when Node then node
      else
        raise Moxml::DocumentStructureError.new(
          "Invalid node type: #{node.class}. Expected String or Moxml::Node",
          operation: "prepare_node",
          state: "node_type: #{node.class}",
        )
      end
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

  module Node
    include NodeBehavior

    # Instantiation shells per type — the contract constants
    # (Element, Text, ...) are modules since issue #230, so wrappers
    # mint through Wrappers::*.
    def self.node_type_map
      @node_type_map ||= {
        element: Wrappers::Element,
        text: Wrappers::Text,
        cdata: Wrappers::Cdata,
        comment: Wrappers::Comment,
        processing_instruction: Wrappers::ProcessingInstruction,
        document: Wrappers::Document,
        declaration: Wrappers::Declaration,
        doctype: Wrappers::Doctype,
        attribute: Wrappers::Attribute,
        entity_reference: Wrappers::EntityReference,
      }.freeze
    end

    # The contract module for a type — what an in-place extended
    # native carries instead of a wrapper shell.
    def self.contract_module(type)
      contract_modules[type]
    end

    def self.contract_modules
      @contract_modules ||= {
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
      wrap_with(node, context, adapter(context))
    end

    # The wrap path with the adapter already resolved — walk entry
    # points know the adapter (it is self); one config-chain hop
    # saved per wrapped node.
    def self.wrap_with(node, context, adapter)
      return nil if node.nil?

      # One C node may have several Ruby representations (leptris
      # native/binding duality, moxml#311); every wrap resolves to
      # the canonical one so memo holders share one invalidation
      # chain. A hit-only lookup: a memoized holder implies a prior
      # walk, which is what populates the canonical map.
      node = adapter.canonical_native(node)

      # Cache-stable binding nodes carry their wrapper directly
      # (#312): the binding's document-owned cache hands the SAME
      # node object for the engine node's whole lifetime, so an
      # ivar is the identity map — one ivar read beats the WeakMap
      # round trip, and the wrapper dies with the node (document
      # scope) exactly like the binding's own wrappers.
      cached = if node.instance_variable_defined?(:@moxml_wrapper)
                 node.instance_variable_get(:@moxml_wrapper)
               else
                 context.wrapper_for(node)
               end
      return cached if cached

      type = adapter.node_type(node)

      # Extend-in-place (issue #230): adapters whose natives can
      # carry the contract modules directly (leptris TypedData) mint
      # the native itself as the wrapper — @native is self. The
      # minted wrapper primes with ITSELF (not the input native):
      # adapter calls then receive the contract-bearing receiver,
      # which klass-propagating reads (#246) dispatch on — and the
      # input native keeps its registration so later wraps of the
      # same base object hit the cache instead of re-minting.
      if (extended = adapter.wrap_native(node, type, context))
        extended.prime_contract(extended, context, adapter, type)
        context.register_wrapper(node, extended)
        context.register_wrapper(extended, extended) unless extended.equal?(node)
        return extended
      end

      klass = node_type_map[type] || Wrappers::Node
      wrapper = klass.new(node, context, adapter, type)
      if node.instance_variable_defined?(:@c_address)
        node.instance_variable_set(:@moxml_wrapper, wrapper)
      else
        context.register_wrapper(node, wrapper)
      end
      wrapper
    end

    def self.adapter(context)
      context.config.adapter
    end

    # Invalidate cached children. Called by mutation methods
    # and by Element attribute/namespace caches.
  end
end
