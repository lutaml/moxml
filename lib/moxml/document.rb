# frozen_string_literal: true

module Moxml
  module Document
    include Node

    attr_accessor :has_xml_declaration

    def initialize(native, context, adapter = nil, node_type = nil)
      super
      @has_xml_declaration = false
    end

    def document
      self
    end

    def root=(element)
      owner = element.is_a?(Node) && element.document
      # Only a genuinely ATTACHED foreign element adopts: the document
      # face answers arbitrary Document wrappers for FLOATING elements
      # (leptris: a stale mint-time document; ox: an Element), and
      # adopting a floating element splices its (empty) copy as root —
      # the caller keeps appending to the detached original and the
      # tree serializes empty (lutaml-model's builder lost every
      # child this way). Attached means parented, or another
      # document's current root.
      attached = !element.parent.nil? ||
        (owner.is_a?(Document) && owner.root.equal?(element))
      if owner.is_a?(Document) && attached &&
          !owner.equal?(self) && element.context.equal?(context)
        installed = adapter.adopt_root(@native, element.native)
        if installed
          # The engine deep-copies the foreign subtree into this
          # document's pool (leptris >= 1.9.292, engine #1495) and the
          # binding memoizes the INSTALLED handle — a fresh pointer.
          # Re-point the source wrapper so later writes reach the live
          # tree, and recompute its scope-derived memos.
          unless installed.equal?(element.native)
            element.refresh_native!(Moxml::Node.wrap(installed, context).native)
            element.invalidate_namespace_cache!
          end
          context.bump_children_generation
          invalidate_children_cache!
          return
        end
        # libleptris refuses a root owned by another document (the
        # engine's set_root ownership check), while Nokogiri adopts.
        # Cross-document CHILD attaches are supported, so build the
        # root here, mirror its declarations and attributes, and
        # splice the foreign subtree child-by-child — each attach
        # rides adapter add_child, which pins the owner document
        # against GC (issue #304).
        new_root = create_element(element.name)
        element.attribute_pairs.each { |k, v| new_root[k] = v }
        element.declared_namespaces.each do |prefix, uri|
          new_root.add_namespace(prefix, uri)
        end
        adapter.set_root(@native, new_root.native)
        new_root.parent_node = self
        element.children.to_a.each { |child| new_root.add_child(child) }
        context.bump_children_generation
        invalidate_children_cache!
        return
      end
      adapter.set_root(@native, element.native)
      element.parent_node = self
      invalidate_children_cache!
    end

    def root
      root_element = adapter.root(@native)
      root_element ? Moxml::Node.wrap(root_element, context) : nil
    end

    # Documents are container nodes: #text concatenates descendant
    # text, Nokogiri's Document#text contract (issue #400) — the base
    # Node#text answered "" and silently emptied consumers'
    # content-preservation checks.
    def text
      val = adapter.text_content(@native)
      entity_bearing? ? adapter.restore_entities(val) : val
    end

    # Materialize the root subtree — see Moxml::Materializer.
    def materialize(&block)
      return to_enum(:materialize) unless block

      root&.materialize(&block)
    end

    # Zero-allocation streaming form over the root subtree (issue
    # #143) — see Moxml::Materializer.
    def materialize_fields(&block)
      raise ArgumentError, "materialize_fields requires a block" unless block

      root&.materialize_fields(&block)
    end

    # Deterministically release the adapter's native memory for this
    # document (issue #134) — batch workloads parsing thousands of
    # documents otherwise hold C trees until GC finalizers run.
    # GC-managed engines no-op. Further access raises the engine's
    # use-after-free error; ordinary garbage-collected documents keep
    # working via the finalizer either way.
    def free
      adapter.free_document(@native)
      nil
    end

    # Parse diagnostics from the engine's recover path (issue #147):
    # [] when the parse was clean, otherwise the recorded error
    # messages. A non-strict leptris parse that came back empty
    # reports the fatal error that emptied it; Nokogiri reports its
    # recover-mode syntax errors; engines without an error channel
    # answer [].
    # Recover-class diagnostics the engine recorded during this
    # document's parse (issue #271): duplicate-attribute
    # recoveries and siblings, as [{ kind:, message: }] in record
    # order. Read while the document is alive — the engine owns
    # the list. [] when the parse was clean or the adapter has no
    # diagnostic surface.
    def parse_diagnostics
      adapter.parse_diagnostics(@native)
    end

    def parse_errors
      adapter.parse_errors(@native)
    end

    # HTML serialization (issue #354): documents parsed through
    # parse_html — and XML documents alike — serialize through the
    # adapter's HTML method: void elements slash-less, raw text
    # (script/style) verbatim, no XML declaration.
    #
    # indent: N (spaces per level) and indent_text: unit (e.g. "\t")
    # thread the pretty-print knobs on adapters that carry them
    # (leptris >= the #354 ride; nokogiri passes them to the
    # engine). Adapters without the knob raise Moxml::AdapterError.
    def to_html(options = {})
      return to_xhtml(options) if options[:xhtml]

      result = adapter.serialize_html(@native, options)
      apply_line_ending(result,
                        options.fetch(:line_ending, Config::LINE_ENDING_LF))
      result
    end

    # XHTML-shaped serialization (issue #390): void elements
    # self-closed (<br/>), non-void elements paired, raw text
    # escaped (the XML method's §16.2-compatible escaping), no
    # declaration unless asked. Composes with the indent knobs.
    # Also selected by to_html(xhtml: true).
    #
    # Byte reference: Nokogiri's FORMAT | AS_XHTML | NO_DECLARATION
    # save flag; canon pins engine-vs-Nokogiri parity on its display
    # corpus before flipping its lane.
    def to_xhtml(options = {})
      result = adapter.serialize_xhtml(@native, options)
      apply_line_ending(result,
                        options.fetch(:line_ending, Config::LINE_ENDING_LF))
      result
    end

    def create_element(name)
      native = adapter.create_element(name, owner_doc: @native)
      # leptris-ruby#508 mints registered klasses at create: the node
      # IS a contract-carrying identity (@native is self) — prime it
      # in place instead of shelling a second wrapper (a raw mint
      # reaching ==/adapter dies on the nil @context).
      return native.prime_contract(native, context, adapter) if native.is_a?(Moxml::Node)

      Wrappers::Element.new(native, context)
    end

    def create_text(content)
      native = adapter.create_text(content, owner_doc: @native)
      return native.prime_contract(native, context, adapter) if native.is_a?(Moxml::Node)

      Wrappers::Text.new(native, context)
    end

    def create_cdata(content)
      Wrappers::Cdata.new(adapter.create_cdata(content, owner_doc: @native), context)
    end

    def create_comment(content)
      Wrappers::Comment.new(adapter.create_comment(content, owner_doc: @native), context)
    end

    def create_doctype(name, external_id, system_id)
      Wrappers::Doctype.new(
        adapter.create_doctype(name, external_id, system_id),
        context,
      )
    end

    def create_processing_instruction(target, content)
      Wrappers::ProcessingInstruction.new(
        adapter.create_processing_instruction(target, content),
        context,
      )
    end

    def create_declaration(version = "1.0", encoding = "UTF-8",
                           standalone = nil)
      decl = adapter.create_declaration(version, encoding, standalone)
      Wrappers::Declaration.new(decl, context)
    end

    def create_entity_reference(name)
      native = adapter.create_entity_reference(name, @native)
      Wrappers::EntityReference.new(native, context)
    end

    # Nokogiri-compatible: Document#name returns "document"
    def name
      "document"
    end

    # Nokogiri-compatible: renaming a document node is a no-op
    def name=(_value); end

    def add_child(node)
      node = prepare_node(node)

      if node.is_a?(Declaration)
        # A proper XML document carries at most one declaration
        # (issue #23).
        if @has_xml_declaration || adapter.has_declaration?(@native, self)
          raise Moxml::ValidationError, "Document already has an XML declaration"
        end

        @has_xml_declaration = true
        adapter.add_child(@native, node.native)
      elsif root && !node.is_a?(ProcessingInstruction) && !node.is_a?(Comment) && !node.is_a?(Doctype)
        raise Error, "Document already has a root element"
      else
        adapter.add_child(@native, node.native)
        # Refresh native for adapters where identity changes (e.g., LibXML doc.root=).
        # Native equality via the adapter, not wrapper !=: re-mints can
        # arrive without context primed (1.9.373 actual_native), and
        # wrapper == dispatches through the adapter (issue #409-class).
        refreshed = adapter.actual_native(node.native, @native)
        node.refresh_native!(refreshed) if refreshed &&
          !adapter.same_node?(refreshed, node.native)
      end
      node.parent_node = self
      invalidate_children_cache!
      self
    end

    # Relative name-test paths on the document resolve laxly, as
    # descendant-or-self anchored at the root — Nokogiri's own
    # Document#at/#search semantics (moxml#393; its #xpath/#at_xpath are
    # strict document-context, where the only element child is the root,
    # and the adapters disagree there anyway: leptris's engine returns []
    # for every relative path — leptris-ruby#502 — while Nokogiri's
    # #at/#xpath disagree with each other). Every strict match survives
    # the lax rewrite (the only strict-matchable first step is the root
    # itself), so this is purely additive. Non-name-test expressions
    # (axes, node types, ".", "..") keep document context.
    RELATIVE_NAME_TEST = /\A\s*(\*|[A-Za-z_][\w.-]*)(\s*\[|\s*\||\z|\/)/

    def xpath(expression, namespaces = nil)
      expression = lax_document_path(expression) if relative_name_test?(expression)

      result = adapter.xpath(@native, expression, namespaces)

      # Handle different result types:
      # - Scalar values (from functions): return directly
      # - NodeSet: already wrapped, return directly
      # - Array / LazyNodeSet: wrap in NodeSet
      case result
      when NodeSet, Float, String, TrueClass, FalseClass, NilClass
        result
      when Array, LazyNodeSet
        NodeSet.new(result, context)
      else
        # For other types, try to wrap in NodeSet
        NodeSet.new(result, context)
      end
    end

    def at_xpath(expression, namespaces = nil)
      expression = lax_document_path(expression) if relative_name_test?(expression)

      if (native_node = adapter.at_xpath(@native, expression, namespaces))
        Moxml::Node.wrap(native_node, context)
      end
    end

    # Quick element creation and addition
    def add_element(name, attributes = {}, &block)
      elem = create_element(name)
      attributes.each { |k, v| elem[k] = v }
      add_child(elem)
      block&.call(elem)
      elem
    end

    # Convenience find methods
    def find(xpath)
      at_xpath(xpath)
    end

    def find_all(xpath)
      xpath(xpath).to_a
    end

    private

    def relative_name_test?(expression)
      expression.match?(RELATIVE_NAME_TEST)
    end

    # Anchor every top-level union branch at the document root
    # ("//"= descendant-or-self): "a/b | c" -> "//a/b | //c" — one
    # adapter call, engine document order preserved, and the
    # attribute-terminal idiom (pinned below) stays intact, which the
    # ".//" form does not (libxml2 rejects .//r/a/@id).
    def lax_document_path(expression)
      split_top_level_unions(expression)
        .map { |branch| "//#{branch.strip}" }
        .join(" | ")
    end

    def split_top_level_unions(expression)
      branches = [+""]
      depth = 0
      quote = nil
      expression.each_char do |ch|
        if quote
          quote = nil if ch == quote
        elsif ["'", '"'].include?(ch)
          quote = ch
        elsif ["(", "["].include?(ch)
          depth += 1
        elsif [")", "]"].include?(ch)
          depth -= 1
        elsif ch == "|" && depth.zero?
          branches << +""
          next
        end
        branches.last << ch
      end
      branches
    end
  end
end
