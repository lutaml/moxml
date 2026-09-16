# frozen_string_literal: true

require "ffi"

return if RUBY_ENGINE == "opal"

require "stringio"
require "leptris"

module Moxml
  module Adapter
    # Adapter over the leptris FFI binding (libleptris C library).
    #
    # libleptris provides DOM parsing, a native XPath 1.0 engine, SAX,
    # and serialization. It has no first-class XML declaration or
    # programmatic DOCTYPE, so those live in CustomizedLeptris value
    # objects stored through NativeAttachment.
    class Leptris < Base
      # The binding floor (issue #149): 1.9.32 carried the traverse
      # fix (leptris-ruby#89) and made built documents reflect their
      # parts immediately (leptris-ruby#91); the document node
      # (1.9.26), DTDATTR (1.9.8), and the batch child-pointer read
      # (1.7.0) surfaces predate it. Older bindings are not eligible
      # for the default (see Config.leptris_preferred_available?) and
      # the adapter no longer carries accommodation paths for them.
      MINIMUM_BINDING_VERSION = "1.9.32"

      # leptris_parse_html_string shipped in bindings 1.9.80
      # (libleptris 1.9.75, engine #659) as Leptris::XML.parse_html.
      HTML_PARSE_SUPPORTED =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.80")

      # Attribute-node xpath results carry proper wrappers since
      # 1.9.105 (leptris-ruby#153: ResultAttr with name/value);
      # before that the native gate routed them to the Ruby engine.
      ATTR_RESULT_NATIVE =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.105")

      # leptris_node_digest shipped in bindings 1.9.99 (libleptris
      # 1.9.99, engine #869): on-demand Merkle subtree hash, zero
      # cost when unused. Below it, Node#digest answers nil.
      DIGEST_SUPPORTED =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.99")

      # 1.9.163.7 added the XPath seams (TODO.perf/15+16):
      # Searchable#at_xpath materializes nodeset entry 0 and frees
      # the handle in one C dispatch — no NodeSet container, no
      # AutoPointer (2.8x on repeat at_xpath) — and
      # CompiledXPath#eval_ptrs runs the compiled handle against
      # raw pointers, skipping the per-call EvaluationContext
      # (~2us on every multi-result query).
      NATIVE_XPATH_SEAMS =
        defined?(::Leptris::XML::Native) &&
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.163.7")

      # Opt-in native read layer (leptris-ruby#185, bindings >= 1.9.162.6):
      # TypedData node wrappers with C-bound hot reads and bulk
      # children construction. Minted from #root downward; the C
      # tree is shared with the binding, so writes made through the
      # bridged binding nodes are visible to native reads. Installs
      # without the compiled bundle (ruby-platform gem) simply stay
      # on the binding path.
      begin
        require "leptris/xml/native_layer"
      rescue LoadError, StandardError
        nil
      end
      NATIVE_READ_LAYER =
        defined?(::Leptris::XML::NativeNode) &&
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.162.6")

      # 1.9.163.2's native layer returns UTF-8, unfrozen strings
      # (1.9.162.x answered ASCII-8BIT — the reads retagged with a
      # dup+force_encoding per call).
      NATIVE_STRINGS_UTF8 =
        defined?(::Leptris::XML::NativeNode) &&
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.163.2")

      # 1.9.163.5 (leptris-ruby#204/#208): native mutations are
      # version-coherent with the binding (both surfaces' memos
      # drop on mutation) — the builder factories and native
      # add_child are adoptable end-to-end; NativeNode grew a
      # document accessor and line numbers.
      NATIVE_MUTATIONS_COHERENT =
        defined?(::Leptris::XML::NativeNode) &&
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.163.5")

      # Identity mode (#230 stage 2): the contract modules extended
      # onto natives shadow the C surface (Element#[] over
      # NativeNode#[]), so the adapter's native fast paths speak to
      # the native layer through these bound entries — bind_call is
      # the same C dispatch without the shadow lookup.
      if NATIVE_READ_LAYER
        NN = ::Leptris::XML::NativeNode
        NN_ATTRIBUTE = NN.instance_method(:attribute)
        NN_NAME = NN.instance_method(:name)
        NN_PARENT = NN.instance_method(:parent)
        NN_NEXT_SIBLING = NN.instance_method(:next_sibling)
        NN_CONTENT = NN.instance_method(:content)
        NN_CHILDREN = NN.instance_method(:children)
        NN_NODE_TYPE = NN.instance_method(:node_type)
        NN_DOCUMENT = NN.instance_method(:document)
        NN_ADD_CHILD = NN.instance_method(:add_child)
      end

      # 1.9.181 (lockstep): Node#source_position — {line, col_start,
      # col_end} from the engine's source-position API (upstream
      # #1124); created nodes report zeros.
      NATIVE_SOURCE_POSITION =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.181")

      # Entity-reference preservation (leptris-ruby#212 / upstream
      # #1094): 1.9.177 ships ParseOptions.keep_entity_refs plus
      # first-class EntityReference nodes — the marker machinery
      # becomes bypassable when the Context's entity_mode is :keep.
      NATIVE_ENTITY_REFS =
        defined?(::Leptris::XML::EntityReference) &&
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.177")

      # 1.9.163.2 moved the native bulk children into C
      # (Native.bulk_children) and fixed the 512 truncation
      # (leptris-ruby#202). The 162.6-163.1 window carries the
      # binding-side truncation, so moxml fetches with its own
      # count-then-copy scratch there; newer bindings use their
      # C bulk path (version-memoized, cheaper than a per-call
      # count+copy).
      NATIVE_BULK_FIXED =
        defined?(::Leptris::XML::NativeNode) &&
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.163.2")

      # Defined unconditionally: the body self-guards, and call
      # sites must never depend on the layer having loaded
      # (issue #217 — binding-only installs crashed on the
      # unguarded bridges).
      # Class-body level: a bare @ivar inside `class << self` lands
      # on the singleton's singleton, invisible to the methods at
      # call time (same shape as @native_doc_roots below).
      @binding_of = ObjectSpace::WeakMap.new

      class << self
        # native -> bridged binding node. The bridge object is
        # identity-stable for the native's lifetime (the binding's
        # per-document wrap cache), so repeat bridges — the write
        # loop on a factory-created element, re-accessed attribute
        # lists — skip the document resolution and pointer wrap.
        # Binding node for any native: identity for binding nodes
        # (and on installs without the native layer — the constant
        # check short-circuits), a Node.wrap over the shared C
        # pointer for NativeNodes.
        def to_binding(node)
          return node unless NATIVE_READ_LAYER &&
            node.is_a?(::Leptris::XML::NativeNode)

          bridged = @binding_of[node]
          return bridged if bridged

          doc = doc_for(node)
          ptr = ::FFI::Pointer.new(node.address)
          bridged = ::Leptris::XML::Node.wrap(ptr, doc)
          @binding_of[node] = bridged unless bridged.nil?
          bridged
        end
      end

      if NATIVE_READ_LAYER
        # root NativeNode -> binding document (recorded at #root
        # mint; the native layer exposes no document accessor).
        @native_doc_roots = ObjectSpace::WeakMap.new

        class << self
          # Extend-in-place mint (#230 stage 2): a TypedData native
          # carries the contract modules on itself — the wrapper layer's
          # 3-4 Ruby frames collapse to the module call over the C
          # method. @native is self; every adapter method that accepts
          # a native already handles NativeNode receivers.
          # Identity mode v2 (#230): wrapper classes SUBCLASS the
          # TypedData native and include the contract modules, and
          # NativeNode.from honors its receiver (klass-injection,
          # 1.9.174.4+): the C wrap mints our class directly — no
          # Ruby-level extend (the v1 extend mint regressed the
          # pipeline 4x; this is the same TypedData wrap the base
          # mint pays). @native is self; the adapter's C-surface
          # bind_calls accept these receivers (they are NativeNode
          # instances). The hot bare reads super into the C methods
          # (exact-name = the bare-name contract).
          module Identity
            ELEMENT = Class.new(::Leptris::XML::NativeNode) do
              include ::Moxml::Node
              include ::Moxml::Element
            end
            TEXT = Class.new(::Leptris::XML::NativeNode) do
              include ::Moxml::Node
              include ::Moxml::Text
            end
            CDATA = Class.new(::Leptris::XML::NativeNode) do
              include ::Moxml::Node
              include ::Moxml::Cdata
            end
            COMMENT = Class.new(::Leptris::XML::NativeNode) do
              include ::Moxml::Node
              include ::Moxml::Comment
            end
            PROCESSING_INSTRUCTION = Class.new(::Leptris::XML::NativeNode) do
              include ::Moxml::Node
              include ::Moxml::ProcessingInstruction
            end

            TYPES = {
              element: ELEMENT,
              text: TEXT,
              cdata: CDATA,
              comment: COMMENT,
              processing_instruction: PROCESSING_INSTRUCTION,
            }.freeze

            module Reads
              # The C methods sit BELOW the contract modules in the
              # ancestry (NativeNode is the superclass), so super
              # from here would run the contract implementation and
              # ADD frames. bind_call reaches the C surface
              # directly; prefixed names take the contract path.
              ELEMENT_CONTRACT_READ =
                ::Moxml::ElementBehavior.instance_method(:[])

              def [](key)
                if key.is_a?(String) && !key.include?(":")
                  value = NN_ATTRIBUTE.bind_call(self, key)
                  return value unless value.is_a?(String) && entity_bearing?

                  return ::Moxml::Adapter::Leptris.restore_entities(value)
                end

                ELEMENT_CONTRACT_READ.bind_call(self, key)
              end

              def text
                value = NN_CONTENT.bind_call(self)
                value.is_a?(String) && entity_bearing? ? ::Moxml::Adapter::Leptris.restore_entities(value) : value
              end
            end
            ELEMENT.include(Reads)
            TEXT.include(Reads)
          end

          NATIVE_IDENTITY =
            NATIVE_MUTATIONS_COHERENT &&
            Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.174.4")

          def wrap_native(node, type, _context)
            return nil unless NATIVE_IDENTITY &&
              node.is_a?(::Leptris::XML::NativeNode)

            # from() registers in the shared address-keyed native
            # cache, so later canonical/bulk mints hand OUR instance
            # back — a native already carrying the contract IS the
            # wrapper; minting again would loop per access.
            return node if node.is_a?(::Moxml::Node)

            klass = Identity::TYPES[type]
            return nil unless klass

            doc = doc_for(node)
            return nil unless doc

            klass.from(doc, node)
          end

          NATIVE_C_WALK =
            defined?(::Leptris::XML::NativeNode) &&
            Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.174.6")

          # One C visit walk (TODO.perf/27: post-order/abort state in
          # the C callback, rb_yield direct — no FFI closure per
          # node) instead of per-level children walks. Pre-order via
          # entering; depth 0 is the receiver and stays unyielded.
          def walk_descendants(native, context)
            return nil unless NATIVE_C_WALK

            root = to_binding(native)
            return nil unless root.is_a?(::Leptris::XML::Element) ||
              root.is_a?(::Leptris::XML::Document)

            root.visit do |node, entering, depth|
              yield Moxml::Node.wrap(node, context) if entering && depth.positive?
            end
          end

          def record_native_doc(root_native, doc)
            @native_doc_roots[root_native] = doc
          end

          # Protocol-level node equality: one engine can hand out
          # two wrapper classes over the same C node (native layer +
          # binding), so raw == is not identity across the seam.
          def same_node?(one, other)
            return true if one.equal?(other)

            if NATIVE_READ_LAYER
              native_one = one.is_a?(::Leptris::XML::NativeNode)
              native_other = other.is_a?(::Leptris::XML::NativeNode)
              if native_one || native_other
                address_one = native_one ? one.address : one.c_ptr.address
                address_other = native_other ? other.address : other.c_ptr.address
                return address_one == address_other
              end
            end

            one == other
          end

          # Binding document for a NativeNode subtree: climb parents
          # to the root (C-bound reads) and look the doc up in the
          # root registry. Detached subtrees answer nil.
          def doc_for(node)
            # The 1.9.163.5 native layer exposes the owning document
            # directly; the root climb serves older bindings.
            return NN_DOCUMENT.bind_call(node) if NATIVE_MUTATIONS_COHERENT

            current = node
            current = current.parent while current&.parent
            @native_doc_roots[current]
          end
        end
      end

      # Binding node for any native: identity for binding nodes, a
      # Node.wrap over the shared C pointer for NativeNodes (used by
      # the write/serialize/namespace paths the native layer does
      # not carry).

      # Native C14N delegation probe: the engine's C14N must
      # byte-match the Ruby reference (ported from canon) on a
      # namespace-sorting + attributes + comments shape before
      # Moxml::C14n hands the default path to it. The engine
      # currently emits namespace declarations in document order
      # instead of lexicographic (filed leptris/leptris#881); the
      # probe auto-adopts the native path once a fixed build lands —
      # no moxml release needed.
      # Lazy, not load-time: the probe exercises the wrapper layer
      # (Document/serialize/C14n), which is circular while THIS
      # adapter file is still loading — the load-time form rescued
      # to false on every build and masked a landed engine fix.
      def self.native_c14n_byte_safe?
        return @native_c14n_byte_safe unless @native_c14n_byte_safe.nil?

        @native_c14n_byte_safe = begin
          probe_xml = %(<?xml version="1.0"?><doc xmlns:p="urn:p" xmlns="urn:d" b="2" a="1"><e p:x="v" z="w">t &amp; u</e><!-- c --></doc>)
          native_doc = ::Leptris::XML::Document.parse(probe_xml)
          native = native_doc.root.canonicalize(
            ::Leptris::XML::FFI::C14N_1_0, nil,
            mode: ::Leptris::XML::FFI::C14N_MODE_CANONICAL
          )
          wrapper = Moxml::Wrappers::Document.new(native_doc, Moxml::Context.new(:leptris))
          reference = Moxml::C14n::Inclusive10.new.canonicalize(wrapper.root)
          native == reference
        rescue StandardError
          false
        end
      end

      # Bumped whenever a document's :entity_markers flag is written
      # (parse, parse_html, entity-reference mint) so wrapper-level
      # entity_bearing? memos invalidate.
      # attr_reader beats the ||= memo on every guarded read (the
      # entity guard consults this per bare read / text read).
      class << self
        attr_reader :serialize_generation
      end
      @serialize_generation = 0

      def self.bump_serialize_generation
        @serialize_generation += 1
      end

      # leptris-ruby#103: prefixed attribute tests inside predicates
      # stopped resolving through the document's in-scope declarations
      # on released 1.9.37–1.9.39; 1.9.40 (engine 1.9.14+) restored
      # the fallback. Older bindings keep the Ruby-engine routing in
      # native_expression?.
      PREFIXED_ATTR_PREDICATES_NATIVE =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.40")

      # leptris/leptris#636 (leptris-ruby 1.9.42): libxml2-compatible
      # pretty-print — child-PI lines, DOCTYPE internal-subset layout,
      # no stray trailing newline after non-ASCII text, and the indent
      # unit (`to_xml`'s indent_text takes the unit string). Older
      # floor bindings treat indent_text as a display-form boolean, so
      # the passthrough and the parity pins gate on this.
      LIBXML2_LAYOUT_PARITY =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.42")

      # leptris-ruby#109 (1.9.45): Element#to_xml takes the
      # indent-unit string, so moxml's per-child document composition
      # can carry `indent_text:` through. Text-bearing leaves still
      # emit spaces until the engine fix (leptris/leptris#658); the
      # boolean display form stays document-level and is never
      # forwarded (the element face raises on it).
      INDENT_UNIT_SUPPORTED =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.45")

      # leptris-ruby#115 (fixed 1.9.50): the element unit path keeps
      # child comments.
      ELEMENT_UNIT_COMMENTS =
        Gem::Version.new(::Leptris::VERSION) >= Gem::Version.new("1.9.50")

      # leptris/leptris#677: the engine's DROP_WS_TEXT trims boundary
      # whitespace of non-blank text nodes. Probed at load rather
      # than version-gated so the C fix is adopted the moment a fixed
      # binding installs — no moxml release needed. While the probe
      # fails, noblanks drops blanks moxml-side after parse.
      ENGINE_NOBLANKS_SAFE = begin
        doc = ::Leptris::XML::Document.parse(
          "<r> x</r>", options: ::Leptris::XML::ParseOptions.noblanks
        )
        text = doc.root.children.first
        text.is_a?(::Leptris::XML::Text) && text.content == " x"
      rescue StandardError
        false
      end

      # leptris/leptris#687: the engine's subset serializer mangles
      # every internal-subset declaration after the first. Probed for
      # the same reason — once fixed, the whole-document fast path
      # serves multi-declaration subsets too.
      ENGINE_MULTI_DECL_SUBSET_OK = begin
        doc = ::Leptris::XML::Document.parse(
          %(<?xml version="1.0"?><!DOCTYPE r [<!ELEMENT r (#PCDATA)><!ATTLIST e a CDATA "d">]><r/>),
        )
        doc.to_xml.include?("<!ATTLIST")
      rescue StandardError
        false
      end

      NO_PARSE_ERRORS = [].freeze
      private_constant :NO_PARSE_ERRORS

      # Cohesive clusters extracted from this class — the adapter
      # protocol surface is unchanged; the modules hold the document
      # parts assembly, the entity-marker pipeline, and the bulk
      # materializer respectively.
      autoload :DocumentParts, "moxml/adapter/leptris/document_parts"
      autoload :Markers, "moxml/adapter/leptris/markers"
      autoload :Materialize, "moxml/adapter/leptris/materialize"
      autoload :Serialize, "moxml/adapter/leptris/serialize"
      autoload :LeptrisSAXBridge, "moxml/adapter/leptris/sax_bridge"
      extend Serialize
      extend DocumentParts
      extend Markers
      extend Materialize

      class << self
        def attachments
          @attachments ||= Moxml::NativeAttachment.new
        end

        def set_root(doc, element)
          to_binding(doc).root = to_binding(element)
        end

        def bare_set_qname_safe?
          true
        end

        def bare_get_qname_safe?
          true
        end

        # Expanded-name (URI + local) attribute VALUE lookup on the
        # engine — the same match rule as the resolver (xmlns
        # declarations invisible, no-namespace never matches a
        # prefixed name), without materializing the attribute list.
        def expanded_attr_reads?
          true
        end

        def native_inclusive10(native)
          return nil unless native_c14n_byte_safe?

          to_binding(native).canonicalize(
            ::Leptris::XML::FFI::C14N_1_0, nil,
            mode: ::Leptris::XML::FFI::C14N_MODE_CANONICAL
          )
        end

        def expanded_attr_value(element, uri, local)
          # Bridge first: identity-mode wrappers hand a NativeNode
          # (no attribute_ns); binding elements pass through as-is.
          # The class-receiver is_a? this method replaced was always
          # false — element.adapter IS the adapter class — so the
          # branch sat dead since identity mode and the binding-only
          # assumption went unnoticed (issue #242).
          to_binding(element).attribute_ns(uri, local)
        end

        # Fast bare-name read: the binding call plus marker
        # restoration when the document carries them (entity-free
        # documents — the common case — skip the scan; parentless
        # iterparse elements are never bearing).
        # Raw qualified-name read; the entity-restore decision is
        # the wrapper's (Element#[] rides its generation memo — the
        # document-plus-attachment probe here cost more than the
        # read itself).
        def bare_attr_value(element, name)
          # Exact-name C read: bare names target no-namespace
          # attributes (the documented contract — a bare "y" never
          # resolves a "p:y" sibling).
          value = if NATIVE_READ_LAYER && element.is_a?(NN)
                    NN_ATTRIBUTE.bind_call(element, name.to_s)
                  else
                    element[name.to_s]
                  end
          if !NATIVE_STRINGS_UTF8 && NATIVE_READ_LAYER &&
              element.is_a?(::Leptris::XML::NativeNode) &&
              value.is_a?(String)
            return value.dup.force_encoding(Encoding::UTF_8)
          end

          value
        end

        def native_identity_stable?
          true
        end

        def parse(xml, options = {}, _context = nil)
          xml_string = xml.is_a?(IO) || xml.is_a?(StringIO) ? xml.read : xml.to_s
          # The marker flag rides preprocess's own `&` scan — no
          # second full-buffer probe (issue #132 parse-side note).
          entity_mode_keep =
            NATIVE_ENTITY_REFS &&
            (_context&.config&.entity_mode == :keep || options[:keep_entity_refs] == true)
          processed, entity_markers =
            if entity_mode_keep
              [xml_string, false]
            else
              Entity.preprocess_with_marker_flag(xml_string)
            end

          # readonly: true (issue #133): the binding memoizes reads and
          # refuses mutations — the parse-and-read lifecycle for
          # multi-pass consumers (comparison, diff, signature).
          # dtdattr: true opts into DTD ATTLIST default materialization
          # (off by default since libleptris 1.9.8, matching libxml2).
          native_doc = begin
            ::Leptris::XML::Document.parse(
              processed,
              readonly: options[:readonly] == true,
              options: parse_flags(options, context: _context),
            )
          rescue ::Leptris::XML::ParseError => e
            # libleptris has no recovery mode that survives unclosed
            # tags; non-strict callers get an empty document, matching
            # the Libxml adapter's non-strict behavior. The fatal
            # error rides the document as parse diagnostics (issue
            # #147) — otherwise nothing says why it came back empty.
            raise Moxml::ParseError.new(e.message) if options[:strict]

            recover_errors = [e.message]
            create_document
          end
          ctx = _context || Context.new(:leptris)
          doc = Wrappers::Document.new(native_doc, ctx)

          if options[:noblanks] && !ENGINE_NOBLANKS_SAFE
            # The engine's DROP_WS_TEXT trims boundary whitespace of
            # NON-blank text nodes at parse (leptris/leptris#677), so
            # the flag is not forwarded — blanks drop here instead.
            if options[:readonly] == true
              raise ArgumentError,
                    "noblanks: true requires a mutable document (readonly: true freezes the tree at parse)"
            end

            strip_blank_text_nodes!(native_doc)
          end

          record_source_declaration(native_doc, processed)
          attachments.set(native_doc, :entity_markers, entity_markers)
          attachments.set(native_doc, :keep_entity_refs, entity_mode_keep)
          bump_serialize_generation
          attachments.set(native_doc, :parse_errors, recover_errors) if recover_errors

          doc
        end

        # Tolerant HTML4/5 parsing into the standard DOM (engine
        # leptris/leptris#659): implied end tags, void elements,
        # raw-text script/style, case-insensitive lowercased names,
        # the HTML named-entity table, synthesized html/head/body.
        # The engine decodes HTML entities directly into text — no
        # marker pipeline, so the marker split scan is stood down.
        # Incremental parse (libleptris v1.6/#586): yields completed
        # elements as the parse runs; each prior subtree is released.
        # Yielded elements are parentless (document nil) and valid
        # only inside the block — the wrapper mirrors that lifetime.
        # Wrapper-parse: the synthetic root's children are the
        # fragment's top-level nodes (the append_xml / inner_xml=
        # trick). Children come through the normal children path so
        # entity-marker splitting applies.
        def parse_fragment(xml, _context = nil)
          doc = parse("<m>#{xml}</m>")
          children(doc.native.root)
        end

        def iterparse(xml, mode = :top_level, _context = nil, &block)
          raise ArgumentError, "iterparse requires a block" unless block

          ctx = _context || Context.new(:leptris)
          ::Leptris::XML::Iterparse.parse(xml, mode: mode) do |element|
            yield(Node.wrap(element, ctx))
          end
        end

        def iterparse_file(path, mode = :top_level, _context = nil, &block)
          raise ArgumentError, "iterparse_file requires a block" unless block

          ctx = _context || Context.new(:leptris)
          ::Leptris::XML::Iterparse.parse_file(path, mode: mode) do |element|
            yield(Node.wrap(element, ctx))
          end
        end

        def parse_html(html, _options = {}, _context = nil)
          unless HTML_PARSE_SUPPORTED
            raise Moxml::AdapterError.new(
              "HTML parsing requires leptris >= 1.9.80 (have #{::Leptris::VERSION})",
              adapter: name, operation: "parse_html",
            )
          end

          html_string = html.is_a?(IO) || html.is_a?(StringIO) ? html.read : html.to_s
          native_doc = begin
            ::Leptris::XML.parse_html(html_string)
          rescue ::Leptris::XML::ParseError => e
            raise Moxml::ParseError.new(e.message)
          end
          attachments.set(native_doc, :entity_markers, false)
          bump_serialize_generation
          Wrappers::Document.new(native_doc, _context || Context.new(:leptris))
        end

        # nil when no parse flag is requested — the binding treats a
        # nil options hash as plain defaults (matching libxml2/
        # Nokogiri semantics: blanks kept, no ATTLIST defaults).
        # noblanks forwards only once the engine flag is libxml2-safe
        # (see ENGINE_NOBLANKS_SAFE); otherwise it is moxml-side.
        def parse_flags(options, context: nil)
          flags = 0
          flags |= ::Leptris::XML::ParseOptions::DTDATTR if options[:dtdattr] == true
          flags |= ::Leptris::XML::ParseOptions::KEEP_ENTITY_REFS if NATIVE_ENTITY_REFS &&
            (context&.config&.entity_mode == :keep ||
             options[:keep_entity_refs] == true)
          flags |= ::Leptris::XML::ParseOptions::NOBLANKS if options[:noblanks] == true && ENGINE_NOBLANKS_SAFE
          flags.zero? ? nil : ::Leptris::XML::ParseOptions.new(flags)
        end

        # XML whitespace exactly — \v and \f are not XML space.
        BLANK_TEXT_RE = /\A[ \t\r\n]*\z/

        # libxml2's XML_PARSE_NOBLANKS semantics (issues #153/#156):
        # drop WHOLLY-whitespace text nodes; the boundary spaces of
        # text-bearing nodes stay (mixed content cannot be
        # re-indented). Raw-pointer walk over the root subtree — the
        # same batch child-pointer pattern the materializer uses.
        def strip_blank_text_nodes!(doc)
          binding_ffi = ::Leptris::XML::FFI
          root = binding_ffi.leptris_document_root(doc.c_ptr)
          return unless root && !root.null?

          strip_blanks_under(root, binding_ffi, ::FFI::MemoryPointer.new(:pointer, 64), 64)
        end

        def strip_blanks_under(ptr, binding_ffi, buf, capacity)
          count = binding_ffi.leptris_node_children(ptr, buf, capacity)
          while count == capacity
            capacity *= 4
            buf = ::FFI::MemoryPointer.new(:pointer, capacity)
            count = binding_ffi.leptris_node_children(ptr, buf, capacity)
          end

          # Snapshot before unlinking or recursing — both reuse the
          # buffer for the next level.
          children = buf.read_array_of_pointer(count)
          children.each do |child|
            case binding_ffi.leptris_node_get_type(child)
            when ::Leptris::XML::FFI::NODE_ELEMENT
              strip_blanks_under(child, binding_ffi, buf, capacity)
            when ::Leptris::XML::FFI::NODE_TEXT
              content = binding_ffi.leptris_text_node_get_content(child)
              next unless content.match?(BLANK_TEXT_RE)

              binding_ffi.check_status(binding_ffi.leptris_node_unlink(child))
            end
          end
        end

        def parse_errors(native_doc)
          attachments.get(native_doc, :parse_errors) || NO_PARSE_ERRORS
        end

        def create_document(_native_doc = nil)
          ::Leptris::XML::Document.create
        end

        # Native builder factories: one C call and a TypedData wrap.
        # Adopted from 1.9.163.5, where native mutations became
        # version-coherent (leptris-ruby#204/#208) — the earlier
        # rejection (stale binding memos + per-attach bridge cost)
        # no longer applies: add_child carries a native fast path.
        def create_native_element(name, owner_doc = nil)
          if NATIVE_MUTATIONS_COHERENT && owner_doc
            return owner_doc.native_create_element(name.to_s)
          end

          (owner_doc || create_document).create_element(name.to_s)
        end

        def create_native_text(content, owner_doc = nil)
          if NATIVE_MUTATIONS_COHERENT && owner_doc
            return owner_doc.native_create_text(content)
          end

          (owner_doc || create_document).create_text_node(content)
        end

        def create_native_cdata(content, owner_doc = nil)
          (owner_doc || create_document).create_cdata(content)
        end

        def create_native_comment(content, owner_doc = nil)
          (owner_doc || create_document).create_comment(content)
        end

        def create_native_processing_instruction(target, content)
          doc = create_document
          doc.create_processing_instruction(target.to_s, content.to_s)
        end

        def create_native_doctype(name, external_id, system_id)
          CustomizedLeptris::Doctype.new(name, external_id, system_id)
        end

        def create_native_declaration(version, encoding, standalone)
          CustomizedLeptris::Declaration.new(version, encoding, standalone)
        end

        def create_native_entity_reference(name, owner_doc = nil)
          if NATIVE_ENTITY_REFS && owner_doc
            return owner_doc.create_entity_reference(name.to_s)
          end

          CustomizedLeptris::EntityReference.new(name)
        end

        def entity_reference_name(node)
          return node.name if NATIVE_ENTITY_REFS &&
            node.is_a?(::Leptris::XML::EntityReference)

          node.name if node.is_a?(CustomizedLeptris::EntityReference)
        end

        def declaration_attribute(declaration, attr_name)
          declaration.public_send(attr_name) if attr_matches?(attr_name)
        end

        def set_declaration_attribute(declaration, attr_name, value)
          declaration.public_send("#{attr_name}=", value) if attr_matches?(attr_name)
        end

        def attr_matches?(attr_name)
          %w[version encoding standalone].include?(attr_name.to_s)
        end
        private :attr_matches?

        def has_declaration?(native_doc, _wrapper)
          return true if attachments.get(native_doc, :declaration)

          attachments.key?(native_doc, :had_source_declaration) &&
            attachments.get(native_doc, :had_source_declaration)
        end

        def remove_declaration(native_doc)
          attachments.delete(native_doc, :declaration)
          attachments.delete(native_doc, :had_source_declaration)
        end

        def create_native_namespace(element, prefix, uri)
          element = to_binding(element) if NATIVE_READ_LAYER
          element.add_namespace_definition(prefix, uri)
        end

        def set_namespace(node, namespace)
          node = to_binding(node) if NATIVE_READ_LAYER
          return set_attribute_namespace(node, namespace) if node.is_a?(::Leptris::XML::Attr)

          element = node
          if namespace.nil?
            # Nil-clear contract (issue #164): undeclare the default
            # namespace (xmlns="") and drop any name prefix — the
            # element then reports no namespace, matching the other
            # adapters. Elements that carried a PREFIX cannot fully
            # detach the engine's namespace link (leptris-ruby#132):
            # the name is unqualified and the undeclaration added, but
            # the serializer may re-attach the old prefix until the
            # engine grows a clear entry.
            element.name = element.name.split(":", 2)[-1] if element.name.include?(":")
            element.default_namespace = ""
            return element
          end
          prefix = namespace.is_a?(String) ? nil : namespace.prefix
          uri = namespace.is_a?(String) ? namespace : namespace.href
          if prefix.nil? || prefix.empty?
            element.default_namespace = uri.to_s
            # Drop any prefix from the element name: a default namespace
            # never applies to a prefixed name.
            element.name = element.name.split(":", 2)[-1] if element.name.include?(":")
          else
            # Name is the local part re-prefixed (a qname create leaves
            # "p:c"; re-joining without the split would double —
            # issue #208). Declare only when the prefix is not already
            # in scope: under a parent that binds p, a bare name set
            # is enough (leptris resolves through ancestors). Detached
            # elements still get the declaration so a standalone
            # serialize stays well-formed.
            local = element.name.split(":", 2)[-1]
            element.name = "#{prefix}:#{local}"
            already = resolve_prefix_ns(element, prefix)
            needs_decl = already.nil? || already.href.to_s != uri.to_s
            # Detached elements that will be attached under a declaring
            # parent must not carry their own declaration — that is
            # the create_element(qname) + namespace= + attach order
            # (issue #208). Standalone serialize of a still-detached
            # namespaced element is the add_namespace caller's job.
            if needs_decl && !element.parent.nil?
              element.add_namespace_definition(prefix, uri.to_s)
            end
          end
          element
        end

        # Attr is an immutable value object: namespace changes go
        # through the owning element, recreating the attribute with a
        # qualified name, and yield a fresh native for the wrapper.
        def set_attribute_namespace(attr, namespace)
          element = attr.element
          local = attr.name.include?(":") ? attr.name.split(":", 2)[1] : attr.name
          value = attr.value
          element.remove_attribute(attr.name)
          prefix = namespace.is_a?(String) ? nil : namespace.prefix
          uri = namespace.is_a?(String) ? namespace : namespace.href
          qualified = prefix.nil? || prefix.empty? ? local : "#{prefix}:#{local}"
          element[qualified] = value
          if prefix && !prefix.empty? && !uri.to_s.empty? && !resolve_prefix_ns(element, prefix)
            element.add_namespace_definition(prefix, uri.to_s)
          end
          element.attribute_nodes.reverse.find { |candidate| candidate.name == qualified }
        end

        def namespace(node)
          node = to_binding(node) if NATIVE_READ_LAYER

          # The binding resolves Attr#namespace to the declaration but
          # without the prefix; when the qualified name carries one,
          # prefer the in-scope declaration that binds it so wrappers
          # keep prefix and uri.
          if node.is_a?(::Leptris::XML::Attr) &&
              (prefix = node.prefix || prefix_part(node.name))
            resolved = resolve_prefix_ns(node.element, prefix)
            return resolved if resolved
          end

          ns = node.namespace
          return ns unless ns.nil?

          # Set-side namespaces (created attributes, renamed elements)
          # carry a prefix the native resolver did not bind; resolve
          # through the scope chain so wrapper-level access stays
          # XML-correct.
          owner = node.is_a?(::Leptris::XML::Attr) ? node.element : node
          prefix = if node.is_a?(::Leptris::XML::Attr)
                     node.prefix || prefix_part(node.name)
                   else
                     prefix_part(node.name)
                   end
          return nil if prefix.nil?

          resolve_prefix_ns(owner, prefix)
        end

        # Nearest in-scope declaration of prefix, walking owner then
        # ancestors. Unbound prefix → nil. Returns the Namespace object
        # so wrappers keep prefix and uri.
        def resolve_prefix_ns(owner, prefix)
          current = owner
          while current.is_a?(::Leptris::XML::Element)
            hit = current.namespace_definitions.find { |ns| ns.prefix == prefix }
            return hit if hit

            current = current.parent
          end
          nil
        end

        def prefix_part(name)
          name.include?(":") ? name.split(":", 2)[0] : nil
        end

        def processing_instruction_target(node)
          return to_binding(node).target if NATIVE_READ_LAYER && node.is_a?(NN)

          node.target
        end

        def node_type(node)
          if NATIVE_READ_LAYER &&
              node.is_a?(::Leptris::XML::NativeNode)
            type = NN_NODE_TYPE.bind_call(node)
            # The native layer spells PIs :pi; the wrapper contract
            # (node_type_map) says :processing_instruction.
            return :processing_instruction if type == :pi

            return type
          end

          # Frequency-ordered: elements and text dominate every real
          # document, and Node.wrap dispatches here once per cold
          # wrap. CDATA must precede Text (CDATA < Text in the
          # binding).
          case node
          when ::Leptris::XML::Element then :element
          when ::Leptris::XML::CDATA then :cdata
          when ::Leptris::XML::Text, CustomizedLeptris::TextSegment then :text
          when ::Leptris::XML::Attr, ::Leptris::XML::ResultAttr then :attribute
          when ::Leptris::XML::Comment then :comment
          when ::Leptris::XML::ProcessingInstruction, CustomizedLeptris::DocumentPI then :processing_instruction
          when ::Leptris::XML::Document then :document
          when ::Leptris::XML::DocType, CustomizedLeptris::Doctype then :doctype
          when CustomizedLeptris::Declaration then :declaration
          when CustomizedLeptris::EntityReference then :entity_reference
          when ::Leptris::XML::EntityReference then :entity_reference if NATIVE_ENTITY_REFS
          else :unknown
          end
        end

        # Subtree digest over the binding node (issue #173). Only
        # binding Nodes carry a C node handle: the synthetic
        # wrappers (declarations, doctypes, entity markers) and the
        # lightweight Attr triples answer nil.
        def digest(node, drop_ws_text: false)
          return nil unless DIGEST_SUPPORTED
          if NATIVE_READ_LAYER && node.is_a?(::Leptris::XML::NativeNode)
            return to_binding(node).digest(drop_ws: drop_ws_text)
          end
          return nil unless node.is_a?(::Leptris::XML::Node) &&
            !node.is_a?(::Leptris::XML::ResultAttr)

          node.digest(drop_ws: drop_ws_text)
        end

        def node_name(node)
          return node.root_name if node.is_a?(::Leptris::XML::DocType)
          return node.target if node.is_a?(CustomizedLeptris::DocumentPI)

          if NATIVE_READ_LAYER && node.is_a?(::Leptris::XML::NativeNode)
            # PIs expose no name through the native layer.
            return to_binding(node).target.to_s if NN_NODE_TYPE.bind_call(node) == :pi

            name = NN_NAME.bind_call(node)
            return name if NATIVE_STRINGS_UTF8

            name.dup.force_encoding(Encoding::UTF_8)
          end

          node.name.to_s.dup.force_encoding("UTF-8")
        end

        def set_node_name(node, name)
          node = to_binding(node) if NATIVE_READ_LAYER
          case node
          when ::Leptris::XML::ProcessingInstruction, CustomizedLeptris::DocumentPI then node.target = name
          else node.name = name
          end
        end

        def duplicate_node(node)
          node = to_binding(node) if NATIVE_READ_LAYER
          case node
          when CustomizedLeptris::Declaration
            CustomizedLeptris::Declaration.new(node.version, node.encoding, node.standalone)
          when CustomizedLeptris::Doctype
            CustomizedLeptris::Doctype.new(node.name, node.external_id, node.system_id)
          when CustomizedLeptris::EntityReference
            CustomizedLeptris::EntityReference.new(node.name)
          when CustomizedLeptris::DocumentPI
            CustomizedLeptris::DocumentPI.new(node.target, node.data, node.parent_doc)
          else
            node.dup
          end
        end

        def children(node, entity_bearing: false)
          # NATIVE_READ_LAYER gates the whole keep-path: it consults
          # NN_DOCUMENT (defined only with the native layer), and
          # native-less installs answer through the binding case
          # branch below, whose children already carry first-class
          # EntityReference nodes (issue #240).
          if NATIVE_READ_LAYER && NATIVE_ENTITY_REFS &&
              native_keep_entity_refs?(node)
            return to_binding(node).children.to_a
          end

          if NATIVE_READ_LAYER && node.is_a?(::Leptris::XML::NativeNode)
            # Bulk C children through moxml's own scratch (see
            # NATIVE_READ_LAYER note above). Entity-marker documents
            # bridge each child for the marker split — the
            # TextSegment reconstruction reads binding text nodes;
            # the wrapper's memo supplies the flag, so deriving it
            # here costs no C parent climb per call.
            natives = if NATIVE_BULK_FIXED
                        NN_CHILDREN.bind_call(node).to_a
                      else
                        bulk_native_children(node)
                      end
            return natives unless entity_bearing

            # Entity-marker documents: bridge for the marker split
            # (TextSegment reconstruction reads binding text nodes).
            doc = doc_for(node)
            bound_children = natives.map { |child| to_binding(child) }
            if doc && attachments.get(doc, :entity_markers) == false
              return bound_children
            end

            return split_entity_markers(bound_children, to_binding(node))
          end
          # Frequency-ordered: elements dominate every walk and paid
          # ten failed compares to reach the else arm.
          case node
          when ::Leptris::XML::Element
            natives = node.children.to_a
            if NATIVE_READ_LAYER && natives.size == 512
              # Binding scratch truncation (leptris-ruby#202): a
              # full batch is ambiguous — refetch through moxml's
              # own buffers to be sure.
              natives = bulk_binding_children(node)
            end
            # Parse records whether the preprocessed source held any
            # entity markers, and the ER builder path flips the flag
            # when it mints one. A false flag lets traversal skip the
            # marker split — including the per-text content fetch that
            # dominates cold children cost. Cross-document moves of
            # marker-bearing text into an entity-free document degrade
            # to literal text.
            return natives if node.document.nil? ||
              attachments.get(node.document, :entity_markers) == false

            split_entity_markers(natives, node)
          when ::Leptris::XML::Document
            assemble_document_children(node)
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference, CustomizedLeptris::TextSegment,
               CustomizedLeptris::DocumentPI,
               # Terminal node kinds pay an FFI round trip for an empty
               # list; unfiltered recursions visit every text node.
               ::Leptris::XML::Text, ::Leptris::XML::Comment,
               ::Leptris::XML::CDATA, ::Leptris::XML::ProcessingInstruction,
               ::Leptris::XML::Attr
            []
          else
            node.children.to_a
          end
        end

        def native_keep_entity_refs?(node)
          return false unless NATIVE_READ_LAYER &&
            node.is_a?(::Leptris::XML::NativeNode)

          doc = NN_DOCUMENT.bind_call(node)
          attachments.get(doc, :keep_entity_refs) == true
        end

        def parent(node)
          if NATIVE_READ_LAYER && node.is_a?(::Leptris::XML::NativeNode)
            parent = NN_PARENT.bind_call(node)
            return parent if parent

            doc = doc_for(node)
            return doc if doc&.root && doc.root.c_ptr.address == node.address

            return nil
          end

          # Frequency-ordered: elements dominate navigation and paid
          # three failed compares to reach the else arm.
          case node
          when ::Leptris::XML::Element then root_parent(node)
          when ::Leptris::XML::Document then nil
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::DocumentPI then node.parent_doc
          when CustomizedLeptris::TextSegment, CustomizedLeptris::EntityReference then node.parent
          # Same body as the Element arm by design (frequency
          # ordering); the generic kinds are cold.
          else root_parent(node) # rubocop:disable Lint/DuplicateBranch
          end
        end

        # Fallback for natives without a registered document: walk
        # first_child/next_sibling at the FFI level and wrap binding
        # nodes over the raw pointers.
        def sibling_walk_children(node)
          ptr = ::FFI::Pointer.new(node.address)
          first = ::Leptris::XML::FFI.leptris_node_first_child(ptr)
          children = []
          current = first
          until current.null?
            children << ::Leptris::XML::Node.wrap(current, nil)
            current = ::Leptris::XML::FFI.leptris_node_next_sibling(current)
          end
          children
        end

        # Native twin for a binding node through the document's
        # address-keyed native cache — minting on miss so every
        # accessor converges on one native per node (issue #219).
        # Binding natives (Attribute/Attr, synthetic wrappers) and
        # docless nodes pass through unchanged.
        def canonical_native(doc, node)
          return node unless node.is_a?(::Leptris::XML::Element)

          cache = doc.native_cache
          cache[node.c_ptr.address] ||=
            ::Leptris::XML::NativeNode.from(doc, node.c_ptr)
        end

        # The binding-node twin of bulk_native_children (identity via
        # the binding's wrap cache).
        def bulk_binding_children(node)
          copied, pointers = bulk_child_buffers(node.c_ptr)
          return node.children.to_a if copied.zero?

          doc = node.document
          Array.new(copied) do |i|
            ::Leptris::XML::Node.wrap(pointers.get_pointer(i * 8), doc)
          end
        end

        # Bulk child fetch with moxml's own grow-to-fit thread-local
        # scratch: count first (exact), size the buffers to it, wrap
        # each pointer as a native-layer node. Correct on every
        # binding version — the binding's own scratch truncates at
        # 512 on 1.9.163.x (leptris-ruby#202).
        def bulk_native_children(node)
          copied, pointers = bulk_child_buffers(::FFI::Pointer.new(node.address))
          return [] if copied.zero?

          doc = doc_for(node)
          if doc.nil?
            # Unregistered native (adapter-level use outside #root):
            # the 163.2 binding's bulk needs a document, so walk
            # siblings instead of crashing through a doc-less wrap.
            return sibling_walk_children(node)
          end

          # Share the layer's per-document identity cache (keyed by
          # node address): NativeNode.from alone mints fresh objects
          # per call on 1.9.163.x, which would fork moxml wrappers.
          cache = doc.native_cache
          Array.new(copied) do |i|
            child_ptr = pointers.get_pointer(i * 8)
            cache[child_ptr.address] ||=
              ::Leptris::XML::NativeNode.from(doc, child_ptr)
          end
        end

        # Shared count-then-copy fetch over moxml's grow-to-fit
        # thread-local scratch — the layer above the binding's
        # (buggy on 1.9.163.x) own buffers. Returns [copied, pointers].
        def bulk_child_buffers(ptr)
          total = ::Leptris::XML::FFI.leptris_node_children_ex(ptr, nil, nil, 0)
          return [0, nil] if total.zero?

          scratch = (Thread.current[:moxml_leptris_children] ||= {})
          pointers = scratch[:pointers]
          if pointers.nil? || pointers.size / 8 < total
            pointers&.free
            pointers = scratch[:pointers] =
              ::FFI::MemoryPointer.new(:pointer, total)
          end
          kinds = scratch[:kinds]
          if kinds.nil? || kinds.size / 4 < total
            kinds&.free
            kinds = scratch[:kinds] = ::FFI::MemoryPointer.new(:int, total)
          end
          copied = ::Leptris::XML::FFI.leptris_node_children_ex(
            ptr, pointers, kinds, total
          )
          [copied, pointers]
        end

        # The binding reports the root element as parentless; the
        # moxml contract roots at the document.
        def root_parent(node)
          node.parent || (node.document&.root == node ? node.document : nil)
        end

        def next_sibling(node)
          return NN_NEXT_SIBLING.bind_call(node) if NATIVE_READ_LAYER &&
            node.is_a?(::Leptris::XML::NativeNode)

          node.next_sibling if node.is_a?(::Leptris::XML::Node)
        end

        def previous_sibling(node)
          # Bridged, not the native sibling walk: the native layer
          # exposes next_sibling only, and its children batch
          # truncates at 512 — the predecessor beyond that would be
          # wrong.
          node = to_binding(node)
          node.previous_sibling if node.is_a?(::Leptris::XML::Node)
        end

        def document(node)
          return doc_for(node) if NATIVE_READ_LAYER &&
            node.is_a?(::Leptris::XML::NativeNode)

          case node
          when ::Leptris::XML::Document then node
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype then node.parent_doc
          else node.document
          end
        end

        def root(document)
          r = document.root
          return nil if r.nil?

          if NATIVE_READ_LAYER
            # Through the same address-keyed cache as the children
            # path: NativeNode.from alone mints a fresh object per
            # call on 1.9.163.x, splitting the wrappers (issue #219).
            native = canonical_native(document, r)
            record_native_doc(native, document)
            return native
          end
          r
        end

        def source_position(node)
          return nil unless NATIVE_SOURCE_POSITION

          to_binding(node).source_position
        end

        def line_number(node)
          if NATIVE_MUTATIONS_COHERENT &&
              node.is_a?(::Leptris::XML::NativeNode)
            line = node.line
            return line.nil? || line.zero? ? nil : line
          end
          return nil unless node.is_a?(::Leptris::XML::Node)

          line = node.line
          line.zero? ? nil : line
        end

        def attributes(element)
          element = to_binding(element)
          element.attribute_nodes
        end

        def attribute_element(attr)
          attr.element
        end

        def attribute_name(attr)
          # leptris Attr names are qualified; the wrapper composes the
          # prefix, so expose the local part.
          return attr.name.split(":", 2)[1] if attr.name.include?(":")

          attr.name.to_s.dup.force_encoding("UTF-8")
        end

        def set_attribute(element, name, value)
          element = to_binding(element) if NATIVE_READ_LAYER
          element[name.to_s] = value.to_s
        end

        def set_attribute_name(attr, name)
          # Attr is an immutable value object; renames go through the
          # element and yield a fresh native, which the wrapper adopts.
          element = attr.element
          value = attr.value
          element.remove_attribute(attr.name)
          element[name.to_s] = value
          element.attribute_nodes.reverse.find { |candidate| candidate.name == name.to_s }
        end

        def set_attribute_value(attr, value)
          attr.value = value.to_s
          attr
        end

        def get_attribute(element, name)
          element = to_binding(element)
          element.attribute_nodes.find { |attr| attr.name == name.to_s }
        end

        def get_attribute_value(element, name)
          element = to_binding(element)
          element[name.to_s]
        end

        def remove_attribute(element, name)
          element = to_binding(element)
          element.remove_attribute(name.to_s)
        end

        def remove_attribute_native(attr)
          attr.element.remove_attribute(attr.name)
          attr
        end

        def add_child(parent, child)
          if NATIVE_READ_LAYER && !(NATIVE_MUTATIONS_COHERENT &&
                   parent.is_a?(::Leptris::XML::NativeNode) &&
                   child.is_a?(::Leptris::XML::NativeNode))
            parent = to_binding(parent)
            child = to_binding(child)
          end
          case parent
          when ::Leptris::XML::Document then add_document_child(parent, child)
          else
            if child.is_a?(CustomizedLeptris::EntityReference)
              marker = parent.document.create_text_node("#{Entity::MARKER}#{child.name};")
              parent.add_child(marker)
              attachments.set(parent.document, :entity_markers, true)
              bump_serialize_generation
              return child
            end
            if NATIVE_MUTATIONS_COHERENT && parent.is_a?(NN) && child.is_a?(NN)
              doc = NN_DOCUMENT.bind_call(parent)
              child = doc.create_text_node(child) if child.is_a?(String)
              return NN_ADD_CHILD.bind_call(parent, child)
            end

            child = parent.document.create_text_node(child) if child.is_a?(String)
            parent.add_child(child)
          end
        end

        def add_previous_sibling(node, new_node)
          if NATIVE_READ_LAYER
            node = to_binding(node)
            new_node = to_binding(new_node)
          end
          # A PI inserted before the root lives at document level in
          # libleptris's model, not in the element tree.
          if new_node.is_a?(::Leptris::XML::ProcessingInstruction) &&
              node.document&.root == node
            node.document.add_pi(new_node.target, new_node.content.to_s)
            return new_node
          end
          node.add_previous_sibling(new_node)
        end

        def add_next_sibling(node, new_node)
          if NATIVE_READ_LAYER
            node = to_binding(node)
            new_node = to_binding(new_node)
          end
          node.add_next_sibling(new_node)
        end

        def remove(node)
          node = to_binding(node) if NATIVE_READ_LAYER
          case node
          when CustomizedLeptris::Declaration
            remove_declaration(node.parent_doc) if node.parent_doc
          when CustomizedLeptris::Doctype
            attachments.delete(node.parent_doc, :doctype) if node.parent_doc
          when CustomizedLeptris::EntityReference
            marker_text_for(node.parent, node.name)&.unlink
          when CustomizedLeptris::DocumentPI
            raise Moxml::NotImplementedError.new(
              "libleptris has no document-level PI removal",
              adapter: :leptris,
              feature: :remove,
            )
          else
            node.unlink
          end
        end

        def replace(node, new_node)
          if NATIVE_READ_LAYER
            node = to_binding(node)
            new_node = to_binding(new_node)
          end
          return node.replace(new_node) if node.is_a?(::Leptris::XML::Element)

          # libleptris only offers element-anchored insertion, so a
          # content node (text/comment/CDATA/PI) is replaced by
          # unlinking and re-inserting: after an element sibling when
          # one exists, else appended (end-of-list) to the parent.
          parent = node.parent
          unless parent
            raise Moxml::DocumentStructureError.new(
              "cannot replace a detached node",
            )
          end

          prev = node.previous_sibling
          node.unlink
          if prev.is_a?(::Leptris::XML::Element)
            prev.add_next_sibling(new_node)
          else
            parent.add_child(new_node)
          end
          new_node
        end

        def replace_children(node, new_children)
          if NATIVE_READ_LAYER
            node = to_binding(node)
            new_children = new_children.map { |child| to_binding(child) }
          end
          node.children = new_children
        end

        def text_content(node)
          if NATIVE_READ_LAYER && node.is_a?(::Leptris::XML::NativeNode)
            content = NN_CONTENT.bind_call(node)
            return content if NATIVE_STRINGS_UTF8

            content.dup.force_encoding(Encoding::UTF_8)
          end

          # Frequency-ordered: elements dominate reads; they paid
          # three failed compares to reach the else arm. The
          # duplicated branch bodies are the point.
          case node
          when ::Leptris::XML::Element, ::Leptris::XML::Text
            node.content.to_s
          when ::Leptris::XML::Document then node.root ? node.root.content : ""
          when CustomizedLeptris::Declaration, CustomizedLeptris::Doctype,
               CustomizedLeptris::EntityReference
            ""
          when CustomizedLeptris::TextSegment then node.content
          else node.content.to_s # rubocop:disable Lint/DuplicateBranch
          end
        end

        def inner_text(node)
          node = to_binding(node) if NATIVE_READ_LAYER
          # moxml semantic: direct text children only — no descendant
          # text (that is #text), no comments. Entity references
          # contribute their serialized form.
          children(node).filter_map do |child|
            case child
            when CustomizedLeptris::EntityReference then "&#{child.name};"
            when ::Leptris::XML::CDATA then child.content
            when ::Leptris::XML::Text, CustomizedLeptris::TextSegment
              child.content.to_s.dup.force_encoding("UTF-8")
            end
          end.join
        end

        def set_text_content(node, content)
          node = to_binding(node) if NATIVE_READ_LAYER
          case node
          when ::Leptris::XML::Document
            node.root&.content = content.to_s
          else
            node.content = content.to_s
          end
        end

        def cdata_content(node)
          return NN_CONTENT.bind_call(node) if NATIVE_READ_LAYER && node.is_a?(NN)

          node.content
        end

        def set_cdata_content(node, content)
          node = to_binding(node) if NATIVE_READ_LAYER
          node.content = content.to_s
        end

        def comment_content(node)
          return NN_CONTENT.bind_call(node) if NATIVE_READ_LAYER && node.is_a?(NN)

          node.content
        end

        def set_comment_content(node, content)
          node = to_binding(node) if NATIVE_READ_LAYER
          node.content = content.to_s
        end

        def processing_instruction_content(node)
          return NN_CONTENT.bind_call(node) if NATIVE_READ_LAYER && node.is_a?(NN)

          node.content
        end

        def set_processing_instruction_content(node, content)
          node = to_binding(node) if NATIVE_READ_LAYER
          node.data = content.to_s
        end

        def namespace_prefix(namespace)
          # Attr#namespace is the bare URI string in leptris 1.9+ (the
          # C model: a namespace handle IS the URI); attributes carry
          # their prefix on the Attr itself.
          return nil if namespace.is_a?(String)

          namespace.prefix
        end

        def namespace_uri(namespace)
          return namespace if namespace.is_a?(String)

          namespace.href
        end

        def namespace_definitions(element)
          element = to_binding(element) if NATIVE_READ_LAYER
          element.namespace_definitions
        end

        def doctype_name(node)
          node.is_a?(CustomizedLeptris::Doctype) ? node.name : node.root_name
        end

        def doctype_external_id(node)
          node.is_a?(CustomizedLeptris::Doctype) ? node.external_id : node.public_id
        end

        def doctype_system_id(node)
          node.system_id
        end

        # XPath prefers libleptris' native C engine (three orders of
        # magnitude faster than the Ruby engine) for document-context
        # queries, with a conservative gate: the Ruby engine handles
        # element-context evaluation (native relative-context
        # semantics are not contract-verified), variable references,
        # and expressions whose results are attribute nodes (native
        # returns those without name accessors). Both engines resolve
        # expression prefixes against document-declared namespaces.
        NATIVE_XPATH_CACHE = XPath::Cache.new(100)
        # The gate decision is expression-intrinsic; re-walking the
        # cached AST three times per xpath call cost ~23% of repeated
        # selective queries, so the boolean caches beside it.
        NATIVE_GATE_CACHE = XPath::Cache.new(100)
        # Root-context queries alone take the parent-axis guard; the
        # AST walk is per-expression, so the verdict caches too.
        PARENT_AXIS_CACHE = XPath::Cache.new(100)

        def xpath(node, expression, namespaces = {})
          node = to_binding(node) if NATIVE_READ_LAYER
          native = native_xpath(node, expression, namespaces)
          return native unless native.nil?

          engine_xpath(node, expression, namespaces)
        end

        def at_xpath(node, expression, namespaces = {})
          native = native_xpath(node, expression, namespaces, first_only: true)
          return native unless native.nil?

          result = engine_xpath(node, expression, namespaces)
          result.is_a?(Array) ? result.first : result
        end

        # @return [Array, Object, nil] native results, or nil when the
        #   query must run on the Ruby engine
        def native_xpath(node, expression, namespaces, first_only: false)
          # Canonical natives (the #219 unification) are bare TypedData
          # wrappers — no Searchable methods, no document handle for
          # the gates below. The memoized bridge recovers the binding
          # identity; without it every element-context query fell to
          # the Ruby engine (a silent native-path loss since #219).
          if NATIVE_READ_LAYER && node.is_a?(::Leptris::XML::NativeNode)
            node = to_binding(node)
          end
          return nil unless native_context_node?(node)
          return nil unless native_expression?(expression)
          # The binding reports the root element parentless while moxml
          # roots it at the document, so parent-axis queries from the
          # root element keep the Ruby engine.
          if node.is_a?(::Leptris::XML::Element) &&
              node.document&.root.equal?(node) &&
              PARENT_AXIS_CACHE.get_or_set(expression) do
                expression_uses_parent_axis?(expression)
              end
            return nil
          end

          compiled = NATIVE_XPATH_CACHE.get_or_set(expression) do
            ::Leptris::XML::XPath.compile(expression)
          end
          document = node.is_a?(::Leptris::XML::Document) ? node : node.document

          if namespaces && !namespaces.empty?
            # Namespace-bound evaluation has no raw-pointer entry —
            # Searchable resolves the ns set for both result shapes.
            result = if first_only
                       node.at_xpath(expression, namespaces)
                     else
                       compiled.eval(node, namespaces)
                     end
            return case result
                   when ::Leptris::XML::NodeSet
                     first_only ? result.first : result.extend(Moxml::LazyNodeSet)
                   else
                     result
                   end
          end

          unless NATIVE_XPATH_SEAMS
            result = compiled.eval(node)
            return case result
                   when ::Leptris::XML::NodeSet
                     first_only ? result.first : result.extend(Moxml::LazyNodeSet)
                   else
                     result
                   end
          end

          # eval_ptrs against raw pointers — the per-call
          # EvaluationContext that #eval builds costs ~2us of Ruby
          # on every query (leptris-ruby TODO.perf/15).
          doc_ptr = node.is_a?(::Leptris::XML::Document) ? node.c_ptr : document.c_ptr
          context_ptr = node.is_a?(::Leptris::XML::Document) ? nil : node.c_ptr
          result_ptr = compiled.eval_ptrs(doc_ptr, context_ptr)
          return nil if result_ptr.null?

          if first_only
            # The single-result seam: nodeset entry 0 materializes
            # and frees in one C dispatch — no NodeSet container, no
            # AutoPointer (leptris-ruby TODO.perf/16). The module
            # object back means a scalar, whose wrap (and free)
            # stays with wrap_xpath_first_result.
            return ::Leptris::XML::Searchable.wrap_xpath_first_result(
              document, result_ptr
            )
          end

          # The binding's #to_a mints one Ruby wrapper per result
          # node; hand the native set through so .size/.first stay
          # native-side (LazyNodeSet holds it unmaterialized).
          # Scalars pass through unwrapped-and-unextended.
          result = ::Leptris::XML::Searchable.wrap_xpath_result(
            document, result_ptr
          )
          result.is_a?(::Leptris::XML::NodeSet) ? result.extend(Moxml::LazyNodeSet) : result
        rescue ::Leptris::XML::XPathError
          # Not supported by the native engine — the Ruby engine is a
          # full XPath 1.0 implementation, including Moxml's syntax
          # errors for invalid expressions.
          nil
        end

        def native_context_node?(node)
          # Parentless elements (iterparse yields) have no document
          # handle for the compiled eval — the Ruby engine owns them.
          return false if node.is_a?(::Leptris::XML::Element) && node.document.nil?

          node.is_a?(::Leptris::XML::Document) ||
            node.is_a?(::Leptris::XML::Element)
        end

        def expression_uses_parent_axis?(expression)
          ast = XPath::Parser.parse_with_cache(expression)
          contains_parent_axis?(ast)
        rescue XPath::SyntaxError
          true
        end

        def contains_parent_axis?(ast)
          return true if ast.type == :parent
          return true if ast.type == :axis && ast.children.first == "parent"

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) && contains_parent_axis?(child)
          end
        end

        # Document-context queries without variable references,
        # attribute-node results, or the nokogiri-compat xmlns:
        # reserved prefix convention.
        def native_expression?(expression)
          NATIVE_GATE_CACHE.get_or_set(expression) do
            ast = XPath::Parser.parse_with_cache(expression)
            next false if ast_contains_type?(ast, :variable)
            next false if uses_xmlns_prefix?(ast)
            next false if !PREFIXED_ATTR_PREDICATES_NATIVE && prefixed_attribute_test?(ast)

            # Attribute-node results are native since 1.9.105
            # (leptris-ruby#153: ResultAttr wrappers with name/value);
            # older bindings returned generic Node wrappers whose
            # #name raised, so the Ruby engine owned them.
            next true if selects_attribute_results?(ast) && ATTR_RESULT_NATIVE

            !selects_attribute_results?(ast)
          end
        rescue XPath::SyntaxError
          false
        end

        def ast_contains_type?(ast, type)
          return true if ast.type == type

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) && ast_contains_type?(child, type)
          end
        end

        # xmlns:name is a nokogiri-compat convention addressing
        # elements in the default namespace; only the Ruby engine
        # implements it.
        def uses_xmlns_prefix?(ast)
          return true if ast.type == :test && ast.value[:namespace] == "xmlns"

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) && uses_xmlns_prefix?(child)
          end
        end

        def selects_attribute_results?(ast)
          case ast.type
          when :pipe, :union, :filter_expr
            ast.children.any? { |child| selects_attribute_results?(child) }
          when :absolute_path, :relative_path
            step = ast.children.last
            step = step.children.first if step.type == :step_with_predicates
            step.type == :axis && step.children.first == "attribute"
          else
            false
          end
        end

        # Released native engines 1.9.37–1.9.39 do not match prefixed
        # attribute tests inside predicates (@p:kind='a'); the Ruby
        # engine does. An attribute test is a :test whose parent axis
        # is "attribute"; bare ones (namespace nil) stay native.
        # Retired above PREFIXED_ATTR_PREDICATES_NATIVE (1.9.40+).
        def prefixed_attribute_test?(ast, parent_axis = nil)
          if ast.type == :test && parent_axis == "attribute"
            ns = ast.value[:namespace]
            return true if ns && !ns.empty? && ns != "xmlns"
          end

          axis = ast.children.first if ast.type == :axis

          ast.children.any? do |child|
            child.is_a?(XPath::AST::Node) &&
              prefixed_attribute_test?(child, axis || (child.type == :axis ? nil : parent_axis))
          end
        end

        def engine_xpath(node, expression, namespaces = {})
          unless node.is_a?(Moxml::Node)
            node = Moxml::Node.wrap(node, Context.new(:leptris))
          end

          ast = XPath::Parser.parse(expression)
          proc = XPath::Compiler.compile_with_cache(ast, namespaces: namespaces)
          result = proc.call(node)

          case result
          when Array, NodeSet
            nodes = result.is_a?(NodeSet) ? result.to_a : result
            seen = {}.compare_by_identity
            nodes.map { |n| n.is_a?(Moxml::Node) ? n.native : n }
              .select do |native|
                if seen.key?(native)
                  false
                else
                  seen[native] = true
                  true
                end
              end
          else
            result
          end
        end

        def sax_parse(xml, handler)
          bridge = LeptrisSAXBridge.new(handler)
          xml_string = xml.is_a?(IO) || xml.is_a?(::StringIO) ? xml.read : xml.to_s
          ::Leptris::XML::SAX::Parser.new(bridge).parse(xml_string)
        rescue ::Leptris::XML::ParseError, ::Leptris::XML::Error => e
          handler.on_error(Moxml::ParseError.new(e.message))
        end

        private

        # The variable-length \s* gap after \A defeats Onigmo's anchor
        # optimization, forcing a full-buffer scan — 6.5 ms on a 1 MB
        # document without a declaration (the common case). Match a
        # head slice instead; fall back to the full string only when
        # the head is all whitespace (pathological prefixes).
        SOURCE_DECLARATION_RE = /\A\s*<\?xml\b/
        private_constant :SOURCE_DECLARATION_RE

        def record_source_declaration(native_doc, xml_string)
          head = xml_string[0, 256]
          had = if head.match?(SOURCE_DECLARATION_RE)
                  true
                elsif head.match?(/\A\s*\z/)
                  xml_string.match?(SOURCE_DECLARATION_RE)
                else
                  false
                end
          attachments.set(native_doc, :had_source_declaration, had)
        end
      end
    end
  end
end
