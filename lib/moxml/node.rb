# frozen_string_literal: true

require_relative "xml_utils"
require_relative "node_set"

module Moxml
  class Node
    include XmlUtils

    TYPES = %i[
      element text cdata comment processing_instruction document
      declaration doctype namespace attribute unknown entity_reference
    ].freeze

    attr_reader :native, :context

    def initialize(native, context)
      @context = context
      @native = native
      @parent_node = nil
    end

    # Update native reference after identity-changing operations
    # (e.g., LibXML doc.root= creates a new Ruby wrapper)
    def refresh_native!(new_native)
      @native = new_native
    end

    def document
      Document.wrap(adapter.document(@native), context)
    end

    def parent
      Moxml::Node.wrap(adapter.parent(@native), context)
    end

    def children
      @children ||= NodeSet.new(
        adapter.children(@native).map { adapter.patch_node(_1, @native) },
        context,
        self,
      )
    end

    def next_sibling
      Moxml::Node.wrap(adapter.next_sibling(@native), context)
    end

    def previous_sibling
      Moxml::Node.wrap(adapter.previous_sibling(@native), context)
    end

    def add_child(node)
      node = prepare_node(node)
      adapter.add_child(@native, node.native)
      # Refresh native in case adapter changed identity (e.g., LibXML doc.root=)
      refreshed = adapter.actual_native(node.native, @native)
      node.refresh_native!(refreshed) if refreshed && refreshed != node.native
      node.parent_node = self
      invalidate_children_cache!
      self
    end

    def add_previous_sibling(node)
      node = prepare_node(node)
      adapter.add_previous_sibling(@native, node.native)
      invalidate_parent_children_cache!
      self
    end

    def add_next_sibling(node)
      node = prepare_node(node)
      adapter.add_next_sibling(@native, node.native)
      invalidate_parent_children_cache!
      self
    end

    def remove
      invalidate_parent_children_cache!
      adapter.remove(@native)
      invalidate_children_cache!
      self
    end

    def replace(node)
      node = prepare_node(node)
      invalidate_parent_children_cache!
      adapter.replace(@native, node.native)
      invalidate_children_cache!
      self
    end

    def to_xml(options = {})
      # Determine if we should include XML declaration
      # For Document nodes: check native then wrapper, unless explicitly overridden
      # For other nodes: default to no declaration unless explicitly set
      serialize_options = default_options.merge(options)
      serialize_options[:no_declaration] = !should_include_declaration?(options)

      result = adapter.serialize(@native, serialize_options)

      # Restore entity markers to named entity references
      adapter.restore_entities(result)
    end

    def xpath(expression, namespaces = {})
      NodeSet.new(adapter.xpath(@native, expression, namespaces), context)
    end

    def at_xpath(expression, namespaces = {})
      Moxml::Node.wrap(adapter.at_xpath(@native, expression, namespaces),
                       context)
    end

    # Convenience find methods (aliases for xpath methods)
    def find(xpath_expression, namespaces = {})
      at_xpath(xpath_expression, namespaces)
    end

    def find_all(xpath_expression, namespaces = {})
      xpath(xpath_expression, namespaces).to_a
    end

    # Check if node has any children
    def has_children?
      !children.empty?
    end

    # Get first/last child
    def first_child
      children.first
    end

    def last_child
      children.last
    end

    # Returns the text content of this node
    # For elements, returns concatenated text of all text children
    # For text nodes, returns the content if available
    def text
      if respond_to?(:content)
        content
      elsif respond_to?(:children)
        children.grep(Text).map(&:content).join
      else
        ""
      end
    end

    # Returns the text content of this node
    # Subclasses should override this method
    # Element and Text have their own implementations
    def text
      ""
    end

    # Attribute accessor - only works on Element nodes
    # Returns nil for non-element nodes
    def [](name)
      return nil unless respond_to?(:attribute)

      attr = attribute(name)
      attr&.value if attr.respond_to?(:value)
    end

    # Returns the namespace of this node
    # Only applicable to Element nodes, returns nil for others
    def namespace
      return nil unless element?

      ns = adapter.namespace(@native)
      ns && Namespace.new(ns, context)
    end

    # Returns all namespace definitions on this node
    # Only applicable to Element nodes, returns empty array for others
    def namespaces
      return [] unless element?

      adapter.namespace_definitions(@native).map do |ns|
        Namespace.new(ns, context)
      end
    end

    # Recursively yield all descendant nodes
    # Used by XPath descendant-or-self and descendant axes
    def each_node(&block)
      children.each do |child|
        yield child
        child.each_node(&block) if child.respond_to?(:each_node)
      end
    end

    # Clone node (deep copy)
    def clone
      Moxml::Node.wrap(adapter.dup(@native), context)
    end
    alias dup clone

    def ==(other)
      self.class == other.class && @native == other.native
    end

    TYPES.each do |node_type|
      define_method "#{node_type}?" do
        adapter.node_type(native) == node_type
      end
    end

    # Returns the primary identifier for this node type
    # For Element: the tag name
    # For Attribute: the attribute name
    # For ProcessingInstruction: the target
    # For content nodes (Text, Comment, Cdata, Declaration): nil (no identifier)
    # For Doctype: nil (not fully implemented across adapters)
    #
    # @return [String, nil] the node's primary identifier or nil
    def identifier
      nil
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
              when :doctype then Doctype
              when :attribute then Attribute
              when :entity_reference then EntityReference
              else self
              end

      klass.new(node, context)
    end

    # Internal: Set the parent node for cache invalidation tracking.
    # Called by NodeSet, Document, Element when establishing parent-child
    # relationships. Public to allow cross-class usage within Moxml internals.
    attr_writer :parent_node

    protected

    def adapter
      context.config.adapter
    end

    def self.adapter(context)
      context.config.adapter
    end

    # Invalidate cached children. Called by mutation methods
    # and by Element attribute/namespace caches.
    def invalidate_children_cache!
      @children = nil
    end

    # Invalidate parent's cached children when this node
    # is removed/replaced from its parent's child list.
    def invalidate_parent_children_cache!
      @parent_node&.invalidate_children_cache!
    end

    private

    def prepare_node(node)
      case node
      when String then Text.new(adapter.create_text(node), context)
      when Node then node
      else
        raise Moxml::DocumentStructureError.new(
          "Invalid node type: #{node.class}. Expected String or Moxml::Node",
          operation: "prepare_node",
          state: "node_type: #{node.class}",
        )
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
        expand_empty: true,
      }
    end

    def should_include_declaration?(options)
      return options[:declaration] if options.key?(:declaration)
      return options.fetch(:declaration, false) unless is_a?(Document)

      # For Document nodes, delegate to adapter for native state check
      adapter.has_declaration?(@native, self)
    end
  end
end
