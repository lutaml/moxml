# frozen_string_literal: true

module Moxml
  module Adapter
    class Base
      # include XmlUtils

      class << self
        include XmlUtils

        def preprocess_entities(xml)
          Entity.preprocess_entities(xml)
        end

        def decode_entities(text)
          Entity.decode_entities(text)
        end

        def restore_entities(text)
          Entity.restore_entities(text)
        end

        def set_root(_doc, _element)
          raise Moxml::NotImplementedError.new(
            "set_root not implemented",
            feature: "set_root",
            adapter: name,
          )
        end

        # Uniform fragment parsing: returns the fragment's top-level
        # nodes as native objects. Engines without a fragment node
        # type (everything but Nokogiri) get the wrapper-parse
        # shape — the same trick Element#append_xml and #inner_xml=
        # use — with a synthetic root whose children are the
        # fragment's top-level nodes.
        def root(_document)
          raise Moxml::NotImplementedError.new(
            "root not implemented", feature: "root", adapter: name
          )
        end

        def parse_fragment(xml, _context = nil)
          doc = parse("<m>#{xml}</m>")
          root = root(doc)
          root ? children(root) : []
        end

        # Streaming incremental parse (leptris engine): yields each
        # completed element while the parse runs, releasing prior
        # subtrees — memory bounded by the largest subtree, not the
        # document. Adapters without an engine iterator raise.
        def iterparse(_xml, _mode = :top_level, _context = nil)
          raise Moxml::AdapterError.new(
            "Streaming iteration is not supported by the #{name.split('::').last} adapter",
            adapter: name, operation: "iterparse",
          )
        end

        def iterparse_file(_path, _mode = :top_level, _context = nil)
          raise Moxml::AdapterError.new(
            "Streaming file iteration is not supported by the #{name.split('::').last} adapter",
            adapter: name, operation: "iterparse_file",
          )
        end

        # Tolerant HTML4/5 parsing into the standard DOM (engine
        # issue leptris/leptris#659): implied end tags, void elements,
        # case-insensitive lowercased names, the HTML named-entity
        # table. Adapters whose engine has an HTML mode override this.
        def parse_html(_html, _options = {}, _context = nil)
          raise Moxml::AdapterError.new(
            "HTML parsing is not supported by the #{name.split('::').last} adapter",
            adapter: name, operation: "parse_html",
          )
        end

        def parse(_xml, _options = {}, _context = nil)
          raise Moxml::NotImplementedError.new(
            "parse not implemented",
            feature: "parse",
            adapter: name,
          )
        end

        # Parse XML using SAX (event-driven) parsing
        #
        # SAX parsing provides a memory-efficient way to process XML
        # by triggering events as the document is parsed, rather than
        # building a complete DOM tree.
        #
        # @param xml [String, IO] XML string or IO object to parse
        # @param handler [Moxml::SAX::Handler] Handler object receiving events
        # @return [void]
        # @raise [Moxml::NotImplementedError] if adapter doesn't support SAX
        def sax_parse(_xml, _handler)
          raise Moxml::NotImplementedError.new(
            "sax_parse not implemented",
            feature: "sax_parse",
            adapter: name,
          )
        end

        # Check if this adapter supports SAX parsing
        #
        # @return [Boolean] true if SAX parsing is supported
        def sax_supported?
          method(:sax_parse).owner != Moxml::Adapter::Base.singleton_class
        end

        def create_document(_native_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_document not implemented",
            feature: "create_document",
            adapter: name,
          )
        end

        # Whether this adapter's #children accepts the
        # entity_bearing: keyword (the built-ins do; downstream
        # overrides may keep the pre-0.5.36 one-argument signature —
        # issue #218). Reflected once per adapter class.
        def children_accepts_entity_flag?
          return @children_accepts_entity_flag unless @children_accepts_entity_flag.nil?

          kinds = %i[key keyrest keyreq]
          @children_accepts_entity_flag =
            method(:children).parameters.any? do |kind, _name|
              kinds.include?(kind)
            end
        end

        # Protocol-level native equality; engines with more than one
        # wrapper class over one C node override (leptris native
        # read layer). Shared adapter examples compare through this.
        # Extend-in-place capability (#230): an adapter whose native
        # objects can carry the contract modules directly returns the
        # extended native here (its @native is itself); the default
        # mints a wrapper shell.
        def wrap_native(_node, _type, _context)
          nil
        end

        # Prefixed-attribute value fast path: adapters whose engine
        # resolves expanded-name (uri, local) lookups natively answer
        # the value here; others fall back to the resolver's
        # attribute-list match. Capability probe, not a class
        # identity check — Moxml::Adapter::Leptris is only defined
        # once that adapter loads (issue #242).
        def expanded_attr_reads?
          false
        end

        def expanded_attr_value(_element, _uri, _local)
          nil
        end

        # Engine-side inclusive C14N delegation: adapters whose
        # engine canonicalizes byte-identically to the Ruby reference
        # answer the String here; others (and unsupported shapes)
        # return nil and the Ruby reference runs. Capability probe —
        # same reasoning as expanded_attr_reads? (issue #242).
        def native_inclusive10(_native)
          nil
        end

        # Source position {line, col_start, col_end} for a node where
        # the engine exposes it (leptris 1.9.181+ source_position);
        # nil elsewhere and for nodes without a position (created
        # nodes answer zeros upstream — pass those through as-is).
        def source_position(_native)
          nil
        end

        # Subtree walk capability: an adapter with a C-side pre-order
        # traversal (leptris >= 1.9.174.6 visit) walks descendants in
        # one dispatch; nil keeps the recursive children walk. Self
        # is not yielded (each_node semantics).
        def walk_descendants(_native, _context)
          nil
        end

        def same_node?(one, other)
          one == other
        end

        # Backends without a native subtree digest answer nil —
        # the wrapper contract Node#digest gates on (issue #173).
        def digest(*)
          nil
        end

        def create_element(name, owner_doc: nil)
          validate_element_name(name)
          create_native_element(name, owner_doc)
        end

        def create_text(content, owner_doc: nil)
          create_native_text(normalize_xml_value(content), owner_doc)
        end

        def create_cdata(content, owner_doc: nil)
          create_native_cdata(normalize_xml_value(content), owner_doc)
        end

        def create_comment(content, owner_doc: nil)
          validate_comment_content(content)
          create_native_comment(normalize_xml_value(content), owner_doc)
        end

        def create_doctype(name, external_id, system_id)
          create_native_doctype(name, external_id, system_id)
        end

        def create_processing_instruction(target, content)
          validate_pi_target(target)
          create_native_processing_instruction(target,
                                               normalize_xml_value(content))
        end

        def create_declaration(version = "1.0", encoding = "UTF-8",
                               standalone = nil)
          validate_declaration_version(version)
          validate_declaration_encoding(encoding)
          validate_declaration_standalone(standalone)
          create_native_declaration(version, encoding, standalone)
        end

        def create_namespace(element, prefix, uri,
namespace_validation_mode: :strict)
          if prefix && uri.to_s.empty?
            raise NamespaceError.new(
              "Prefixed namespace declaration cannot have an empty URI",
              prefix: prefix,
              uri: uri,
            )
          end
          if namespace_validation_mode == :strict
            validate_prefix(prefix) if prefix
            validate_uri(uri, mode: :strict)
          else
            validate_uri(uri, mode: :lenient)
          end
          create_native_namespace(element, prefix, uri)
        end

        def create_entity_reference(name, owner_doc = nil)
          validate_entity_reference_name(name)
          create_native_entity_reference(name, owner_doc)
        end

        # Mutation return contract: protocol methods that may change
        # which native a wrapper tracks (set_attribute_name,
        # set_namespace, set_attribute_value) always return the native
        # the wrapper must keep tracking — the same object when
        # mutated in place, a fresh object when the adapter recreates
        # the node.
        def set_attribute_name(attribute, name)
          attribute.name = name
          attribute
        end

        def set_namespace(_node, _namespace)
          raise Moxml::NotImplementedError.new(
            "set_namespace not implemented",
            feature: "set_namespace",
            adapter: name,
          )
        end

        def set_attribute_value(attribute, value)
          attribute.value = value
          attribute
        end

        # Remove a specific native attribute node from its owning
        # element. Semantics (which attribute a name addresses) live
        # in Moxml::AttributeResolver; this is the raw primitive.
        def remove_attribute_native(attr)
          attr.remove
        end

        def entity_reference_name(node)
          node.name
        end

        def duplicate_node(node)
          node.dup
        end

        def patch_node(node, _parent = nil)
          # monkey-patch the native node if necessary
          node
        end

        # Whether children() results need per-child patch_node
        # rewriting. Adapters whose natives arrive pre-wrapped (all but
        # ox and libxml) answer false so the wrapper layer can skip
        # the identity map over every child list.
        def patches_children?
          false
        end

        # Whether add_child can keep tracking the same native —
        # adapters that may recreate the node on attach (libxml's
        # doc.root=) override to false so the wrapper refresh path
        # stays armed.
        def native_identity_stable?
          false
        end

        # Whether a BARE-name attribute READ addresses only the
        # no-namespace attribute (qualified-name semantics) — the
        # gate for Element#[]'s fast path (bare_attr_value).
        # Differs per engine: rexml's bare read returns a namespaced
        # sibling's value; oga's raw values need resolver-only
        # marker restoration.
        def bare_get_qname_safe?
          false
        end

        # Whether set_attribute with a BARE name behaves as a
        # qualified-name write: replaces only the no-namespace
        # attribute and never touches a namespaced p:<local> sibling.
        # Verified per engine; oga's repeated bare writes diverge, so
        # it stays false there and assign keeps the full resolve.
        def bare_set_qname_safe?
          false
        end

        # Generation of adapter-level state that cached serialize
        # decisions depend on (leptris: the entity-marker document
        # flag). Bumping invalidates wrapper-level memos; adapters
        # whose answers are static keep the constant zero.
        def serialize_generation
          0
        end

        # Whether the subtree at native can contain entity markers.
        # Marker-tracking adapters override this so the post-serialize
        # restore can skip its full-output scans on marker-free
        # documents; the default stays conservative.
        def entity_bearing?(_native, _doc = nil)
          true
        end

        # Whether the engine offers a bulk materialization path for
        # Materializer (issue #132). When true, the adapter gets
        # #materialize_fields(native, buffers, &block) — fill the
        # reused flat buffers and yield the eight record fields per
        # node. Returning nil (e.g. for document shapes the bulk path
        # cannot express) falls back to the generic wrapper walk.
        def bulk_materialize?
          false
        end

        def materialize_fields(_native, _buffers)
          nil
        end

        # Read-only attribute listing as [name, value] pairs
        # (Moxml::Element#attribute_pairs) — document order,
        # duplicates included, no Attribute node wrappers. The
        # walk-hot shape for consumers that only read name/value;
        # mutation and per-attribute namespace resolution stay on
        # #attributes. This default derives from #attributes;
        # adapters with a bulk face override (leptris answers in
        # one C crossing — leptris-ruby#278).
        def attribute_pairs(element)
          attributes(element).map do |attr|
            [attribute_name(attr), attr.value.to_s]
          end
        end

        # Plan row stream (Moxml::Plan) — ADAPTER CONTRACT. Yields
        # |name, attrs_pairs (flat [k, v, ...]), first-text, depth|
        # per element in document order (pre-order); first-text is
        # the element's first text child or nil. Adapters implement
        # this natively off their engine nodes (nokogiri, ox, oga,
        # rexml, libxml, leptris do) — Moxml::Plan executes entirely
        # on these rows with no wrapper materialization. This default
        # returns nil, which makes Moxml::Plan fall back to the
        # generic wrapper walk — correct but slow; last resort only.
        def plan_rows(_native)
          nil
        end

        # Struct-plan executor (Moxml::StructPlan): +spec+ compiles
        # the consumer's shape as {name => [Struct class, attrs
        # Hash (name => slot Symbol), text slot, children slot]}.
        # Returns the array of top-level minted structs, or nil when
        # the adapter has no C executor (the StructPlan then runs
        # its Moxml::Plan fallback over plan_rows).
        def plan_structs(_native, _spec)
          nil
        end

        # Deterministic native-memory release for adapters backed by
        # C trees (issue #134). GC-managed engines no-op; released
        # documents raise the engine's use-after-free error on
        # further access.
        def free_document(_native)
          nil
        end

        # Parse diagnostics (issue #271): recover-class events the
        # engine recorded during the parse — duplicate-attribute
        # recoveries and siblings — as [{ kind:, message: }] in
        # record order, [] for a clean parse. Reads must happen
        # while the native document is alive (the engine owns the
        # list); adapters without the surface answer []. Distinct
        # from #parse_errors (the strict-parse failure channel):
        # diagnostics describe RECOVERED documents.
        def parse_diagnostics(_native_doc)
          []
        end

        # Recover-mode parse diagnostics (issue #147): the error
        # messages the engine recorded while parsing, [] when the
        # parse was clean. Engines with a native recover channel
        # (Nokogiri's `doc.errors`) or a non-strict path that loses
        # the raised error (leptris) override this.
        def parse_errors(_native_doc)
          []
        end

        # Check if the native document has an XML declaration
        # @param native_doc the native document object
        # @param wrapper [Moxml::Document] the wrapper with has_xml_declaration flag
        # @return [Boolean]
        def has_declaration?(_native_doc, wrapper)
          wrapper.has_xml_declaration
        end

        # Clear the declaration state from the native document.
        # Called when a Declaration node is removed from a document.
        def remove_declaration(_native_doc); end

        # Source line of a native node (1-based), or nil when the
        # underlying backend does not track source positions.
        # Adapters that track lines (Nokogiri, LibXML) override this.
        def line_number(_node)
          nil
        end

        # Local name of a native attribute node. Adapters whose natives
        # carry qualified names override this to expose the local part;
        # the wrapper composes the prefix.
        def attribute_name(attr)
          attr.name
        end

        # Return the actual native node after an add_child operation.
        # Override for adapters where node identity may change (e.g., LibXML doc.root=).
        def actual_native(child_native, _parent_native)
          child_native
        end

        # Whether `Node.wrap` may safely memoize the wrapper for this
        # native across calls. Adapters whose parser hands back the
        # same Ruby object for the same logical node (nokogiri, ox,
        # oga, rexml, leptris) opt in (default true). Adapters that
        # mint a new Ruby object per access (libxml) opt out so the
        # identity map does not accumulate dead entries.
        def wrappers_recyclable?
          true
        end

        # Returns all namespaces in scope for this element, including
        # inherited from ancestors. Adapters with native support (Nokogiri)
        # override this. Default walks the ancestor chain.
        def in_scope_namespaces(element)
          namespaces = {}
          node = element

          while node
            break unless node_type(node) == :element

            namespace_definitions(node).each do |ns|
              prefix = namespace_prefix(ns)
              namespaces[prefix] = ns unless namespaces.key?(prefix)
            end
            node = parent(node)
          end

          namespaces.values
        end

        protected

        def create_native_element(_name, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_element not implemented",
            feature: "create_native_element",
            adapter: name,
          )
        end

        def create_native_text(_content, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_text not implemented",
            feature: "create_native_text",
            adapter: name,
          )
        end

        def create_native_cdata(_content, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_cdata not implemented",
            feature: "create_native_cdata",
            adapter: name,
          )
        end

        def create_native_comment(_content, _owner_doc = nil)
          raise Moxml::NotImplementedError.new(
            "create_native_comment not implemented",
            feature: "create_native_comment",
            adapter: name,
          )
        end

        def create_native_doctype(_name, _external_id, _system_id)
          raise Moxml::NotImplementedError.new(
            "create_native_doctype not implemented",
            feature: "create_native_doctype",
            adapter: name,
          )
        end

        def create_native_processing_instruction(_target, _content)
          raise Moxml::NotImplementedError.new(
            "create_native_processing_instruction not implemented",
            feature: "create_native_processing_instruction",
            adapter: name,
          )
        end

        def create_native_declaration(_version, _encoding, _standalone)
          raise Moxml::NotImplementedError.new(
            "create_native_declaration not implemented",
            feature: "create_native_declaration",
            adapter: name,
          )
        end

        def create_native_namespace(_element, _prefix, _uri)
          raise Moxml::NotImplementedError.new(
            "create_native_namespace not implemented",
            feature: "create_native_namespace",
            adapter: name,
          )
        end

        def create_native_entity_reference(_name)
          raise Moxml::NotImplementedError.new(
            "create_native_entity_reference not implemented",
            feature: "create_native_entity_reference",
            adapter: name,
          )
        end
      end
    end
  end
end
