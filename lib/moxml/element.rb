require_relative "attribute"
require_relative "namespace"

module Moxml
  class Element < Node
    def name
      adapter.node_name(@native)
    end

    def name=(value)
      adapter.set_node_name(@native, value)
    end

    def []=(name, value)
      adapter.set_attribute(@native, name, normalize_xml_value(value))
    end

    def [](name)
      adapter.get_attribute(@native, name)&.value
    end

    def attribute(name)
      native_attr = adapter.get_attribute(@native, name)
      native_attr && Attribute.new(native_attr, context)
    end

    def attributes
      adapter.attributes(@native).map do |attr|
        Attribute.new(attr, context)
      end
    end

    def remove_attribute(name)
      adapter.remove_attribute(@native, name)
      self
    end

    def add_namespace(prefix, uri)
      validate_uri(uri)
      ns = adapter.create_namespace(@native, prefix, uri)
      adapter.set_namespace(@native, ns) if ns
      self
    rescue ValidationError => err
      raise Moxml::NamespaceError, err.message
    end

    def namespace
      ns = adapter.namespace(@native)
      ns && Namespace.new(ns, context)
    end

    def namespaces
      adapter.namespace_definitions(@native).map do |prefix, uri|
        Namespace.new([prefix, uri], context)
      end
    end

    def namespace=(ns)
      adapter.set_namespace(@native, ns&.native)
    end

    def text
      adapter.text_content(@native)
    end

    def text=(content)
      adapter.set_text_content(@native, normalize_xml_value(content))
      self
    end

    def inner_html
      adapter.inner_html(@native)
    end

    def inner_html=(html)
      doc = context.parse("<root>#{html}</root>")
      adapter.replace_children(@native, doc.root.children.map(&:native))
      self
    end

    # Fluent interface methods
    def with_attribute(name, value)
      self[name] = value
      self
    end

    def with_namespace(prefix, uri)
      add_namespace(prefix, uri)
      self
    end

    def with_text(content)
      self.text = content
      self
    end
  end
end
