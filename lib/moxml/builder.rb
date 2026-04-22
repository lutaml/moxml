# frozen_string_literal: true

module Moxml
  class Builder
    attr_reader :document
    alias_method :doc, :document

    def initialize(context)
      @context = context
      @current = @document = context.create_document
      @namespaces = {}
    end

    def build(&block)
      instance_eval(&block)
      @document
    end

    def declaration(version: "1.0", encoding: "UTF-8", standalone: nil)
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
        return create_element_node("element", name_or_attrs, block: block, eval_block: false)
      end

      create_element_node(name_or_attrs, attributes, block: block, eval_block: true)
    end

    def text(content)
      @current.add_child(@document.create_text(content))
    end

    def cdata(content)
      @current.add_child(@document.create_cdata(content))
    end

    def comment(content)
      @current.add_child(@document.create_comment(content))
    end

    def entity_reference(name)
      @current.add_child(@document.create_entity_reference(name))
    end

    def processing_instruction(target, content)
      @current.add_child(
        @document.create_processing_instruction(target, content),
      )
    end

    def namespace(prefix, uri)
      @current.add_namespace(prefix, uri)
      @namespaces[prefix] = uri
    end

    # Convenience method for DOCTYPE
    def doctype(name, external_id = nil, system_id = nil)
      @current.add_child(
        @document.create_doctype(name, external_id, system_id),
      )
    end

    # Batch element creation
    def elements(element_specs)
      element_specs.each do |name, content_or_attrs|
        if content_or_attrs.is_a?(Hash)
          element(name, content_or_attrs)
        else
          element(name) { text(content_or_attrs) }
        end
      end
    end

    # Helper for creating namespaced elements
    def ns_element(namespace_uri, name, attributes = {}, &block)
      el = element(name, attributes, &block)
      prefix = @namespaces.key(namespace_uri)
      el.namespace = { prefix => namespace_uri } if prefix
      el
    end

    # Dynamic element creation DSL.
    # xml.schema(attrs) { } creates <schema> with those attributes.
    # Uses yield so blocks preserve the caller's self context.
    def method_missing(method_name, *args, &block)
      attrs = args.first.is_a?(Hash) ? args.first : {}
      text_content = args.first.is_a?(String) ? args.first : nil

      create_element_node(method_name.to_s, attrs, text_content: text_content,
                                                    block: block, eval_block: false)
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end

    private

    # Single method for all element creation.
    # eval_block: true  → instance_eval (build DSL context)
    # eval_block: false → yield (preserves caller's self)
    def create_element_node(tag_name, attrs = {}, text_content: nil, block: nil, eval_block: true)
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
        eval_block ? instance_eval(&block) : block.call
        @current = previous
      end

      el
    end
  end
end
