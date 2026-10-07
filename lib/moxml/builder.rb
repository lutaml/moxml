# frozen_string_literal: true

module Moxml
  class Builder
    RESERVED_METHOD_PATTERN = /\A(to_|as_json|marshal_|inspect|freeze|dup|clone)/

    attr_reader :document
    alias_method :doc, :document

    def initialize(context)
      @context = context
      @current = @document = context.create_document
      @namespaces = {}
      # Markup-accumulating face (leptris 1.9.313, #374 lever 2):
      # leaf DSL ops write markup into one String and a single
      # native crossing flushes the whole subtree at build end.
      # Tree-only ops (declaration/doctype/PI/entity/namespace)
      # flush first and run on the document; the face retires after
      # its first flush.
      @face = context.config.adapter.builder_face(@document.native)
      @face_stack = []
      @face_counts = Hash.new(0)
      @face_deferred = []
      @face_entity_markers = false
    end

    def build(&block)
      instance_eval(&block)
      flush_face
      @document
    end

    # Element ops inside a face-accumulated subtree cannot touch the
    # tree yet (nothing exists until the flush): PIs ride the raw
    # hatch in exact position; namespace/entity/declaration/doctype
    # defer to the flush and re-target their element by position (an
    # element's namespace set is unordered, so deferral is exact;
    # deferred children land at their element's end).
    def face_defer(operation, args)
      @face_deferred << [operation, args, @face_stack.dup]
    end

    def declaration(version: "1.0", encoding: "UTF-8", standalone: nil)
      args = [version, encoding, standalone]
      return face_defer(:declaration, args) if @face && @face_stack.any?

      flush_face
      @current.add_child(
        @document.create_declaration(version, encoding, standalone),
      )
    end

    # When called with a String name: creates element via instance_eval (DSL block context).
    # When called with a Hash (e.g., element(name: "foo")): creates <element> tag
    # via yield — handles collision where "element" is both a builder method
    # and a valid XML tag name (XSD/RelaxNG).
    def element(name_or_attrs = nil, attributes = {}, &block)
      if name_or_attrs.is_a?(Hash)
        return create_element_node("element", name_or_attrs, block: block,
                                                             eval_block: false)
      end

      raise ArgumentError, "element requires a tag name" if name_or_attrs.nil?

      create_element_node(name_or_attrs, attributes, block: block,
                                                     eval_block: true)
    end

    def text(content)
      return face_content { @face.text(content) } if @face

      @current.add_child(@document.create_text(content))
    end

    def cdata(content)
      return face_content { @face.cdata(content) } if @face

      @current.add_child(@document.create_cdata(content))
    end

    def comment(content)
      return face_content { @face.comment(content) } if @face

      @current.add_child(@document.create_comment(content))
    end

    def entity_reference(name)
      # In-position through the marker face: the reference lands as
      # marker text exactly where the DSL puts it, and the flush
      # arms the document's entity-marker restoration.
      if @face && @face_stack.any?
        @face.raw("#{Entity::MARKER}#{name};")
        @face_entity_markers = true
        return
      end

      flush_face
      @current.add_child(@document.create_entity_reference(name))
    end

    def processing_instruction(target, content)
      if @face
        if @face_stack.empty?
          flush_face
        else
          @face.raw("<?#{target} #{content}?>")
          return
        end
      end
      @current.add_child(
        @document.create_processing_instruction(target, content),
      )
    end

    def namespace(prefix, uri)
      return face_defer(:namespace, [prefix, uri]) if @face && @face_stack.any?

      flush_face
      @current.add_namespace(prefix, uri)
      @namespaces[prefix] = uri
    end

    # Convenience method for DOCTYPE
    def doctype(name, external_id = nil, system_id = nil)
      args = [name, external_id, system_id]
      return face_defer(:doctype, args) if @face && @face_stack.any?

      flush_face
      @current.add_child(
        @document.create_doctype(name, external_id, system_id),
      )
    end

    # Batch element creation
    # Dynamic element creation DSL.
    # xml.schema(attrs) { } creates <schema> with those attributes.
    # Uses yield so blocks preserve the caller's self context.
    # Supported call shapes: (), (String), (Hash), (String, Hash).
    def method_missing(method_name, *args, &block)
      return super if RESERVED_METHOD_PATTERN.match?(method_name.to_s)

      text_content = args.first.is_a?(String) ? args.shift : nil
      attrs = args.first.is_a?(Hash) ? args.shift : {}

      unless args.empty?
        raise ArgumentError,
              "unexpected arguments for #{method_name}: #{args.inspect}"
      end

      if text_content && block
        raise ArgumentError,
              "#{method_name}: cannot combine text content with a block"
      end

      # Strip trailing underscore to allow reserved Ruby method names as tags
      # (e.g., type_, class_, id_ become <type>, <class>, <id>)
      tag_name = method_name.to_s.chomp("_")

      create_element_node(tag_name, attrs, text_content: text_content,
                                           block: block, eval_block: false)
    end

    def respond_to_missing?(method_name, _include_private = false)
      return super if RESERVED_METHOD_PATTERN.match?(method_name.to_s)

      true
    end

    FACE_NAME = /\A[a-zA-Z_][\w.-]*\z/
    FACE_ESCAPE = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;",
                    '"' => "&quot;" }.freeze
    FACE_ESCAPE_RE = /[&<>"]/

    private

    # One face.element per DSL element — the face opens/closes the
    # markup around the block itself, so nesting is free. Prefixed
    # names (p:tag) fall outside the face's name shape and ride the
    # raw hatch with manual escaping. Returns no wrapper: nothing
    # exists until the flush.
    def face_element(tag_name, attrs, text_content, block, eval_block)
      unless FACE_NAME.match?(tag_name)
        return face_raw_element(tag_name, attrs, text_content, block,
                                eval_block)
      end

      face_attrs = {}
      attrs.each do |key, value|
        k = key.to_s
        if k == "xmlns" || k.start_with?("xmlns:")
          face_attrs[k] = value.to_s
          @namespaces[k.delete_prefix("xmlns:")] = value.to_s
        else
          face_attrs[k] = value
        end
      end
      ordinal = @face_counts[@face_stack.length]
      @face_counts[@face_stack.length] = ordinal + 1
      @face_stack << ordinal
      begin
        @face.element(tag_name, face_attrs) do
          @face.text(text_content) if text_content
          run_builder_block(block, eval_block) if block
        end
      ensure
        @face_stack.pop
        @face_counts.delete(@face_stack.length + 1)
      end
    end

    def face_raw_element(tag_name, attrs, text_content, block, eval_block)
      open = "<#{tag_name}"
      attrs.each do |key, value|
        k = key.to_s
        if k == "xmlns" || k.start_with?("xmlns:")
          @namespaces[k.delete_prefix("xmlns:")] = value.to_s
        end
        open << " " << k << '="' << face_escape(value) << '"'
      end
      ordinal = @face_counts[@face_stack.length]
      @face_counts[@face_stack.length] = ordinal + 1
      @face_stack << ordinal
      begin
        if block || text_content
          @face.raw("#{open}>")
          @face.text(text_content) if text_content
          run_builder_block(block, eval_block) if block
          @face.raw("</#{tag_name}>")
        else
          @face.raw("#{open}/>")
        end
      ensure
        @face_stack.pop
        @face_counts.delete(@face_stack.length + 1)
      end
    end

    # Content at document level has no root to attach to and the
    # Document face flush demands exactly one root — retire the face
    # and take the tree path (legacy semantics: doc-level text is a
    # document child). Inside a subtree the text accumulates in
    # position; @current never leaves the document in face mode, so
    # the face stack is the nesting test.
    def face_content
      return yield if @face && @face_stack.any?

      flush_face if @face
    end

    def run_builder_block(block, eval_block)
      eval_block ? instance_eval(&block) : block.call
    end

    def face_escape(value)
      value.to_s.gsub(FACE_ESCAPE_RE, FACE_ESCAPE)
    end

    def flush_face
      return unless @face

      face = @face
      @face = nil
      face.flush
      if @face_entity_markers
        @context.config.adapter.mark_entity_markers(@document.native)
      end
      apply_face_deferred
    end

    # Deferred tree-ops re-target their element by position: the
    # stack records each element's ordinal among its parent's
    # elements, and the flushed tree preserves markup order.
    def apply_face_deferred
      @face_deferred.each do |op, args, stack|
        target = @document.root
        stack[1..].each do |ordinal|
          target = target.elements.to_a[ordinal]
        end
        case op
        when :namespace
          target.add_namespace(*args)
          @namespaces[args[0]] = args[1]
        when :declaration
          target.add_child(@document.create_declaration(*args))
        when :doctype
          target.add_child(@document.create_doctype(*args))
        end
      end
      @face_deferred = []
    end

    # Single method for all element creation.
    # eval_block: true  → instance_eval (build DSL context)
    # eval_block: false → yield (preserves caller's self)
    def create_element_node(tag_name, attrs = {}, text_content: nil,
block: nil, eval_block: true)
      if @face
        face_element(tag_name, attrs, text_content, block, eval_block)
        return nil
      end

      el = @document.create_element(tag_name)

      attrs.each do |key, value|
        if key.to_s == "xmlns"
          el.add_namespace(nil, value.to_s)
        elsif key.to_s.start_with?("xmlns:")
          prefix = key.to_s.sub("xmlns:", "")
          el.add_namespace(prefix, value.to_s)
        else
          el[key] = value
        end
      end

      @current.add_child(el)

      el.add_child(@document.create_text(text_content)) if text_content

      if block
        previous = @current
        @current = el
        begin
          eval_block ? instance_eval(&block) : block.call
        ensure
          @current = previous
        end
      end

      el
    end
  end
end
