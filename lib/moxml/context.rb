# frozen_string_literal: true

module Moxml
  class Context
    # Opal's default runtime excludes ObjectSpace entirely; the weak
    # registry needs WeakMap, so the strong Hash (with its
    # wholesale-clear valve) covers that platform.
    WEAK_WRAPPERS = !defined?(ObjectSpace::WeakMap).nil?
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
    end

    def wrapper_for(native)
      @wrappers[native]
    end

    def register_wrapper(native, wrapper)
      # Adapter opt-in. Adapters whose natives are recreated per
      # access (libxml mints fresh Ruby objects for the same C node)
      # opt out so the map does not accumulate dead entries; the
      # default is opt-in.
      return if @config&.adapter&.wrappers_recyclable? == false

      # The strong fallback (Opal) needs the wholesale-clear valve;
      # the WeakMap registry is self-cleaning.
      @wrappers.clear if @wrappers.is_a?(Hash) && @wrappers.size >= 65_536
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
      Document.new(config.adapter.create_document(native_doc), self)
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
      has_declaration = xml_string.match?(/\A[ \t\r\n\f\v\0]*<\?xml/)

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

    # Streaming incremental parse (leptris): yields each completed
    # element while parsing — :top_level yields the root's children,
    # :full_document every element in completion (post-order) order.
    # Memory stays bounded by the largest subtree, not the document
    # (iterparse_file streams the file C-side). Yielded elements are
    # parentless and valid only inside the block.
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

      # Delegate to adapter
      config.adapter.sax_parse(xml, handler)
    end

    def build(&block)
      Builder.new(self).build(&block)
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
