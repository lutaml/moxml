# frozen_string_literal: true

module Moxml
  class Context
    # Opal's default runtime excludes ObjectSpace entirely; the weak
    # registry needs WeakMap, so the strong Hash (with its
    # wholesale-clear valve) covers that platform.
    # MRI 3.3's ObjectSpace::WeakMap has a mark-time hazard: a
    # dangling VALUE in the weak table is dereferenced during
    # incremental-GC marking (SIGSEGV in wmap_mark_weak_table_i —
    # lutaml/moxml#303, reproduced with the leptris adapter on the
    # xmi suite; 100% crash rate 1.9.261-1.9.282, clean with these
    # registries strong). Ruby 3.4 rewrote WeakMap and is safe.
    # MRI < 3.4 takes the strong identity-Hash fallback (the Opal
    # shape, with the 65,536 valve in register_wrapper).
    # Ruby >= 4.0 joins the strong fallback (ruby#489 / #487 class):
    # 4.0's GC rework drops the weak wrapper entries mid-hydration —
    # orphaned Leptris documents, freed pools, segfaults in
    # leptris_element_get_document and 'Memory allocation failed' on
    # the adoption walk. The gate reads as a version ALLOWLIST of
    # WeakMap semantics we have validated, not a floor.
    WEAK_WRAPPERS = !defined?(ObjectSpace::WeakMap).nil? &&
      !(RUBY_ENGINE == "ruby" &&
        (Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4") ||
         Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("4.0")))
    attr_reader :config

    def initialize(adapter = nil)
      @config = Config.new(adapter)
      # Bumped on any namespace-scope mutation; Element scope caches
      # compare against it so every wrapper sees changes without
      # needing wrapper identity.
      @namespace_scope_generation = 0
      # Native → wrapper identity map: repeated traversals hand back
      # the same wrapper instead of allocating a fresh one per
      # access. Keyed by object identity; re-keyed by
      # Node#refresh_native! when an adapter swaps a native.
      # WeakMap where available: entries die with their native —
      # parse-and-drop workloads release wrappers, natives, and (via
      # the binding's finalizer) the C subtrees, instead of pinning
      # up to the old 65,536 wholesale-clear valve which also
      # destroyed identity for live wrappers when it fired.
      @wrappers = WEAK_WRAPPERS ? ObjectSpace::WeakMap.new : {}.compare_by_identity
      # Static per context (the registry flavor never changes).
      @wrappers_strong = !WEAK_WRAPPERS
      # Resolved on first registration — the adapter-resolution
      # chain ran per mint and the decision never changes for a
      # context's adapter (re-configuring an adapter mid-context is
      # unsupported: minted wrappers already carry the old one).
      @register_wrappers = nil
    end

    def wrapper_for(native)
      @wrappers[native]
    end

    def register_wrapper(native, wrapper)
      # Adapter opt-in, resolved once (see initialize): adapters
      # whose natives are recreated per access (libxml mints fresh
      # Ruby objects for the same C node) opt out so the map does
      # not accumulate dead entries; the default is opt-in.
      if @register_wrappers.nil?
        @register_wrappers =
          @config&.adapter&.wrappers_recyclable? != false
      end
      return unless @register_wrappers

      # The strong fallback (Opal) needs the wholesale-clear valve;
      # the WeakMap registry is self-cleaning.
      @wrappers.clear if @wrappers_strong && @wrappers.size >= 65_536
      @wrappers[native] = wrapper
    end

    # WeakMap has no delete — a nil value tombstones the entry (reads
    # as a miss) and dies with the native like any other.
    def unregister_wrapper(native)
      if WEAK_WRAPPERS
        @wrappers[native] = nil
      else
        @wrappers.delete(native)
      end
    end

    # Children-memo generation: bumped by every tree mutation so
    # per-wrapper children memos can self-invalidate even when the
    # same logical node is reachable through multiple wrapper
    # representations (native vs binding duality).
    def children_generation
      @children_generation ||= 0
    end

    def bump_children_generation
      @children_generation = children_generation + 1
    end

    def namespace_scope_generation
      @namespace_scope_generation
    end

    def bump_namespace_scope_generation
      @namespace_scope_generation += 1
    end

    def entity_registry
      @entity_registry ||= build_entity_registry
    end

    def create_document(native_doc = nil)
      Wrappers::Document.new(config.adapter.create_document(native_doc), self)
    end

    def parse(xml, options = {})
      xml_string = if xml.is_a?(String)
                     xml
                   else
                     xml.read.tap do
                       xml.rewind if xml.is_a?(IO) || xml.is_a?(StringIO)
                     end
                   end
      # Allocation-free declaration sniff: String#strip would copy the
      # whole buffer just to test its prefix.
      # Invalid byte sequences would raise from the regex before any
      # adapter sees them; the adapters' named parse errors own
      # malformed input (taxonomy differential, malformed class).
      has_declaration = xml_string.valid_encoding? &&
        xml_string.match?(/\A[ \t\r\n\f\v\0]*<\?xml/)

      # Parse with adapter, passing self (context) so adapter can use our config
      parsed_options = default_options.merge(options)
      doc = config.adapter.parse(xml_string, parsed_options, self)

      # Set declaration flag on Document wrapper (proper OOP)
      doc.has_xml_declaration = has_declaration if doc.is_a?(Document)

      doc
    end

    # Tolerant HTML4/5 parsing into the standard DOM: implied end
    # tags, void elements, case-insensitive lowercased names, the
    # HTML named-entity table, synthesized html/head/body. Supported
    # by adapters with an engine HTML mode (leptris >= 1.9.80,
    # nokogiri); others raise Moxml::AdapterError.
    def parse_html(html, options = {})
      config.adapter.parse_html(html, options, self)
    end

    # WHATWG fragment parse (issue #353): the parsed top-level
    # nodes with fragment semantics — the context element's
    # insertion mode governs tree construction (:body default keeps
    # head-swept elements at fragment top level; the table
    # contexts take the in-table rules). Returns an
    # Moxml::HtmlFragment whose #children are the moxml-wrapped
    # top-level nodes.
    #
    # @param html [String, IO] the fragment source
    # @param context_tag [Symbol] :body (default) or a table
    #   context (:td, :th, :tr, :tbody, :thead, :tfoot, :caption,
    #   :colgroup, :table)
    # @return [Moxml::HtmlFragment]
    # @raise [Moxml::AdapterError] on adapters without fragment
    #   support or an unknown context tag
    def parse_html_fragment(html, context_tag: :body)
      html_string = html.is_a?(IO) || html.is_a?(StringIO) ? html.read : html.to_s
      HtmlFragment.new(
        config.adapter.parse_html_fragment(html_string, context_tag, self),
        self,
      )
    end

    # Compile an XSLT stylesheet with this context's adapter
    # (implementation-agnostic; nokogiri/libxslt and leptris ship
    # engines, leptris covering XSLT 2.0/3.0 per its engine). Apply
    # the returned Stylesheet to documents parsed by this context.
    #
    # @param stylesheet [String, Moxml::Document] the stylesheet
    #   source; documents from other adapters serialize through their
    #   own adapter first
    # @return [Moxml::XSLT::Stylesheet]
    # @raise [Moxml::NotImplementedError] on adapters without an engine
    # @raise [Moxml::XsltError] on a malformed stylesheet
    # Compile an XSD schema for validation (moxml XSD contract).
    # Returns a Moxml::XSD::Schema; #validate/#valid? take a node or
    # raw XML string. Adapters without an engine raise
    # Moxml::NotImplementedError; Moxml::XSD.supported?(self)
    # answers without raising.
    #
    # @raise [Moxml::NotImplementedError] on adapters without a validator
    def xsd(schema_source)
      handle = config.adapter.xsd_compile(schema_source.to_s)
      Moxml::XSD::Schema.new(handle, self)
    end

    # Compile an XSD schema from a file path — <xs:include href>
    # resolves relative to the file's directory (the engine
    # resolves it; reading the file into #xsd would lose that).
    def xsd_file(path)
      handle = config.adapter.xsd_compile_file(path.to_s)
      Moxml::XSD::Schema.new(handle, self)
    end

    # Compile a RELAX NG schema from source or from a file path (the
    # engine resolves relative includes against the file's directory).
    # Adapters without an RNG engine raise Moxml::NotImplementedError.
    def relaxng(schema_source)
      handle = config.adapter.relaxng_compile(schema_source.to_s)
      Moxml::RelaxNG::Schema.new(handle, self)
    end

    def relaxng_file(path)
      handle = config.adapter.relaxng_compile_file(path.to_s)
      Moxml::RelaxNG::Schema.new(handle, self)
    end

    def xslt(stylesheet)
      source = case stylesheet
               when Moxml::Document then stylesheet.to_xml
               else stylesheet.to_s
               end
      sheet = config.adapter.xslt_compile(source)
      Moxml::XSLT::Stylesheet.new(sheet, self)
    end

    # Streaming incremental parse (leptris): yields each completed
    # element while parsing — :top_level yields the root's children,
    # :full_document every element in completion (post-order) order.
    # Memory stays bounded by the largest subtree, not the document
    # (iterparse_file streams the file C-side). Yielded elements are
    # parentless and valid only inside the block.
    # Parse an XML fragment: returns its top-level nodes as an
    # Array of wrappers, uniformly across adapters (issue #188 —
    # fragment: true was Nokogiri-only). Engines without a fragment
    # node type parse inside a synthetic root; the fragment's nodes
    # are the result either way.
    def parse_fragment(xml)
      adapter = config.adapter
      adapter.parse_fragment(xml, self).map do |node|
        # Adapters that tie a parent_node lifetime chain (#245)
        # return wrapped nodes — pass them through untouched;
        # re-wrapping would race the weak wrapper map.
        node.is_a?(Moxml::Node) ? node : Moxml::Node.wrap(node, self)
      end
    end

    def iterparse(xml, mode: :top_level, &block)
      config.adapter.iterparse(xml, mode, self, &block)
    end

    def iterparse_file(path, mode: :top_level, &block)
      config.adapter.iterparse_file(path, mode, self, &block)
    end

    # Parse then flatten in one call — see Moxml::Materializer
    # (issue #132). Yields records; returns an Enumerator when no
    # block is given.
    def materialize(xml, options = {}, &block)
      parse(xml, options).materialize(&block)
    end

    # Parse then stream the zero-allocation field form (issue #143) —
    # see Moxml::Materializer.
    def materialize_fields(xml, options = {}, &block)
      raise ArgumentError, "materialize_fields requires a block" unless block

      parse(xml, options).materialize_fields(&block)
    end

    # Parse XML using SAX (event-driven) parsing
    #
    # SAX parsing is memory-efficient and suitable for large XML files.
    # Provide either a handler object or a block with DSL.
    #
    # @param xml [String, IO] XML string or IO object to parse
    # @param handler [Moxml::SAX::Handler, nil] Handler object (optional if block given)
    # @yield [block] DSL block for defining handlers (optional if handler given)
    # @return [void]
    # @raise [ArgumentError] if neither handler nor block is provided
    #
    # @example With handler object
    #   handler = MyHandler.new
    #   context.sax_parse(xml_string, handler)
    #
    # @example With block
    #   context.sax_parse(xml_string) do
    #     start_element { |name, attrs| puts name }
    #     characters { |text| puts text }
    #   end
    #
    def sax_parse(xml, handler = nil, &block)
      # Create block handler if block given
      handler ||= SAX::BlockHandler.new(&block) if block

      # Validate handler
      raise ArgumentError, "Handler or block required" unless handler
      unless handler.is_a?(SAX::Handler)
        raise ArgumentError, "Handler must inherit from Moxml::SAX::Handler"
      end

      # Loud degradation: an engine that cannot report an event family
      # raises the named error when the handler subscribes, rather than
      # answering a silently incomplete stream (model, SAX).
      SAX::Handler::EVENT_METHODS.each_key do |family|
        next unless handler.handles?(family)
        next if config.adapter.sax_event_family_supported?(family)

        raise Moxml::NotImplementedError.new(
          "SAX #{family} events are not supported by the " \
          "#{config.adapter.name.split('::').last} adapter",
          feature: "sax_#{family}",
          adapter: config.adapter.name,
        )
      end

      # Delegate to adapter
      config.adapter.sax_parse(xml, handler)
    end

    # strict: (issue #371) flips unknown method_missing calls to
    # NoMethodError instead of silently creating empty elements —
    # nil defers to config.builder_strict.
    def build(strict: nil, &block)
      Builder.new(self, strict: strict).build(&block)
    end

    # Frozen serialization defaults, memoized per context — Node#to_xml
    # merged these from live config reads on every call (bulk element
    # serialization pays a hash build + 4 chain derefs per element).
    def default_serialize_options
      @default_serialize_options ||= {
        encoding: config.default_encoding,
        indent: config.default_indent,
        line_ending: config.default_line_ending,
        expand_empty: true,
      }.freeze
    end

    # The argless element.to_xml form resolves every option statically
    # (no declaration for non-document nodes, context defaults for the
    # rest) — this prebuilt frozen hash makes that path allocation-free.
    def default_element_serialize_options
      @default_element_serialize_options ||=
        default_serialize_options.merge(no_declaration: true).freeze
    end

    private

    def build_entity_registry
      registry = EntityRegistry.new(
        mode: config.entity_load_mode,
        entity_provider: config.entity_provider,
      )
      config.preload_entity_sets.each do |set_name|
        case set_name
        when :html5 then registry.load_html5
        when :mathml then registry.load_mathml
        when :iso then registry.load_iso
        end
      end
      registry
    end

    def default_options
      {
        encoding: config.default_encoding,
        strict: config.strict_parsing,
        indent: config.default_indent,
        ox_skip: config.ox_skip,
        ox_mode: config.ox_mode,
      }
    end
  end
end
