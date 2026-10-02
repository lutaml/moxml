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
      # The document face can answer non-Document objects for floating
      # elements on some adapters (ox) — only a real foreign Document
      # counts as a cross-document root.
      if owner.is_a?(Document) && !owner.equal?(self) && element.context.equal?(context)
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

    def create_element(name)
      Wrappers::Element.new(adapter.create_element(name, owner_doc: @native), context)
    end

    def create_text(content)
      Wrappers::Text.new(adapter.create_text(content, owner_doc: @native), context)
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
        # Refresh native for adapters where identity changes (e.g., LibXML doc.root=)
        refreshed = adapter.actual_native(node.native, @native)
        node.refresh_native!(refreshed) if refreshed && refreshed != node.native
      end
      node.parent_node = self
      invalidate_children_cache!
      self
    end

    def xpath(expression, namespaces = nil)
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
  end
end
