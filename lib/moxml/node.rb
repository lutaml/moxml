# frozen_string_literal: true

require_relative "xml_utils"
require_relative "node_set"

module Moxml
  class Node
    include XmlUtils

    TYPES = %i[
      element text cdata comment processing_instruction document
      declaration doctype namespace attribute unknown
    ].freeze

    attr_reader :native, :context

    def initialize(native, context)
      @context = context
      # @native = adapter.patch_node(native)
      @native = native
    end

    def document
      Document.wrap(adapter.document(@native), context)
    end

    def parent
      Node.wrap(adapter.parent(@native), context)
    end

    def children
      NodeSet.new(
        adapter.children(@native).map { adapter.patch_node(_1, @native) },
        context,
      )
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
      # Determine if we should include XML declaration
      # For Document nodes: check native then wrapper, unless explicitly overridden
      # For other nodes: default to no declaration unless explicitly set
      serialize_options = default_options.merge(options)
      serialize_options[:no_declaration] = !should_include_declaration?(options)

      adapter.serialize(@native, serialize_options)
    end

    def xpath(expression, namespaces = {})
      NodeSet.new(adapter.xpath(@native, expression, namespaces), context)
    end

    def at_xpath(expression, namespaces = {})
      Node.wrap(adapter.at_xpath(@native, expression, namespaces), context)
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
        children.select { |c| c.is_a?(Text) }.map(&:content).join
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

    # Returns all ancestor nodes from parent up to document
    # @return [NodeSet] collection of ancestor nodes
    def ancestors
      result = []
      current = parent
      while current
        result << current.native
        current = current.parent rescue nil
      end
      NodeSet.new(result, context)
    end

    # Returns all descendant nodes (children, grandchildren, etc.)
    # @return [NodeSet] collection of descendant nodes
    def descendants
      result = []
      each_node { |node| result << node.native }
      NodeSet.new(result, context)
    end

    # Returns the XPath expression to locate this node
    # @return [String] XPath path to this node
    def path
      adapter.path(@native)
    end

    # Returns the line number where this node appears in the source XML
    # @return [Integer, nil] line number or nil if not available
    def line_number
      adapter.line_number(@native)
    end

    # Clone the node (deep copy)
    def clone
      Node.wrap(adapter.dup(@native), context)
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

      # For Document nodes, check both wrapper flag and native state
      # Wrapper flag is set by Context.parse for parsed documents
      # Native state reflects programmatic changes (e.g., add/remove)

      adapter_name = adapter.to_s.split("::").last

      case adapter_name
      when "Nokogiri"
        # Nokogiri: if @xml_decl is explicitly set, use that state
        # Otherwise, trust wrapper flag (for parsed documents)
        if native.respond_to?(:instance_variable_defined?) &&
            native.instance_variable_defined?(:@xml_decl)
          # Explicitly set (programmatically added) - check if nil
          !native.instance_variable_get(:@xml_decl).nil?
        else
          # Not set (parsed document) - trust wrapper flag
          has_xml_declaration
        end
      when "Rexml"
        # REXML: check @xml_declaration instance variable
        # If not defined (parsed doc), trust wrapper flag
        if native.respond_to?(:instance_variable_defined?) &&
            native.instance_variable_defined?(:@xml_declaration)
          # Explicitly set - check if nil
          !native.instance_variable_get(:@xml_declaration).nil?
        else
          # Not set (parsed document) - trust wrapper flag
          has_xml_declaration
        end
      when "Oga"
        native.respond_to?(:xml_declaration) && !native.xml_declaration.nil?
      when "Ox", "HeadedOx"
        # Ox stores declaration in document attributes
        native[:version] || native[:encoding] || native[:standalone]
      when "Libxml"
        # LibXML stores declaration wrapper as instance variable
        if native.respond_to?(:instance_variable_defined?) &&
            native.instance_variable_defined?(:@moxml_declaration)
          # Explicitly set - check if nil
          !native.instance_variable_get(:@moxml_declaration).nil?
        else
          # Not set - trust wrapper flag
          has_xml_declaration
        end
      else
        # Fallback - trust wrapper flag
        has_xml_declaration
      end
    end
  end
end
