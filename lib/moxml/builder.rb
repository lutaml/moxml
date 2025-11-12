# frozen_string_literal: true

module Moxml
  class Builder
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

    def element(name, attributes = {}, &block)
      el = @document.create_element(name)

      attributes.each do |key, value|
        if key.to_s == "xmlns"
          # Handle default namespace
          el.add_namespace(nil, value.to_s)
        elsif key.to_s.start_with?("xmlns:")
          # Handle prefixed namespace
          prefix = key.to_s.sub("xmlns:", "")
          el.add_namespace(prefix, value.to_s)
        else
          # Regular attribute
          el[key] = value
        end
      end

      @current.add_child(el)

      if block
        previous = @current
        @current = el
        instance_eval(&block)
        @current = previous
      end

      el
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
  end
end
