require_relative "xml_utils"
require_relative "node_set"

module Moxml
  class Node
    include XmlUtils

    attr_reader :native, :context

    def initialize(native, context)
      @native = native
      @context = context
    end

    def document
      Document.wrap(adapter.document(@native), context)
    end

    def parent
      Node.wrap(adapter.parent(@native), context)
    end

    def children
      NodeSet.new(adapter.children(@native), context)
    end

    def next_sibling
      Node.wrap(adapter.next_sibling(@native), context)
    end

    def previous_sibling
      Node.wrap(adapter.previous_sibling(@native), context)
    end

    def add_child(node)
      node = prepare_node(node)
      adapter.add_child(@native, node.native)
      self
    end

    def add_previous_sibling(node)
      node = prepare_node(node)
      adapter.add_previous_sibling(@native, node.native)
      self
    end

    def add_next_sibling(node)
      node = prepare_node(node)
      adapter.add_next_sibling(@native, node.native)
      self
    end

    def remove
      adapter.remove(@native)
      self
    end

    def replace(node)
      node = prepare_node(node)
      adapter.replace(@native, node.native)
      self
    end

    def to_xml(options = {})
      encode_mode = options.delete(:encode_mode)

      encode_entities(
        adapter.serialize(@native, default_options.merge(options)),
        encode_mode
      )
    end

    def xpath(expression, namespaces = {})
      NodeSet.new(adapter.xpath(@native, expression, namespaces), context)
    end

    def at_xpath(expression, namespaces = {})
      Node.wrap(adapter.at_xpath(@native, expression, namespaces), context)
    end

    def ==(other)
      self.class == other.class && @native == other.native
    end

    def self.wrap(node, context)
      return nil if node.nil?

      klass = case adapter(context).node_type(node)
        when :element then Element
        when :text then Text
        when :cdata then Cdata
        when :comment then Comment
        when :processing_instruction then ProcessingInstruction
        when :document then Document
        when :declaration then Declaration
        else self
        end

      klass.new(node, context)
    end

    protected

    def adapter
      context.config.adapter
    end

    def self.adapter(context)
      context.config.adapter
    end

    private

    def prepare_node(node)
      case node
      when String then Text.new(adapter.create_text(node), context)
      when Node then node
      else
        raise ArgumentError, "Invalid node type: #{node.class}"
      end
    end

    def default_options
      {
        encoding: context.config.default_encoding,
        indent: context.config.default_indent,
        # The short format of empty tags in Oga and Nokogiri isn't configurable
        # Oga: <empty /> (with a space)
        # Nokogiri: <empty/> (without a space)
        # The expanded format is enforced to avoid this conflict
        expand_empty: true
      }
    end
  end
end
