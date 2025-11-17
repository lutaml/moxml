# frozen_string_literal: true

module Moxml
  class NodeSet
    include Enumerable

    attr_reader :nodes, :context

    def initialize(nodes, context)
      @nodes = Array(nodes)
      @context = context
    end

    def each
      return to_enum(:each) unless block_given?

      nodes.each { |node| yield Node.wrap(node, context) }
      self
    end

    def [](index)
      case index
      when Integer
        Node.wrap(nodes[index], context)
      when Range
        NodeSet.new(nodes[index], context)
      end
    end

    def first
      Node.wrap(nodes.first, context)
    end

    def last
      Node.wrap(nodes.last, context)
    end

    def empty?
      nodes.empty?
    end

    def size
      nodes.size
    end
    alias length size

    def to_a
      map { |node| node }
    end

    def +(other)
      self.class.new(nodes + other.nodes, context)
    end

    def <<(node)
      # If it's a wrapped Moxml node, unwrap to native before storing
      native_node = node.respond_to?(:native) ? node.native : node
      @nodes << native_node
      self
    end
    alias push <<

    # Deduplicate nodes based on native object identity
    # This is crucial for XPath operations like descendant-or-self
    # which may yield the same native node multiple times
    def uniq_by_native
      seen = {}
      unique_natives = @nodes.select do |native|
        id = native.object_id
        if seen[id]
          false
        else
          seen[id] = true
          true
        end
      end
      self.class.new(unique_natives, context)
    end

    def ==(other)
      self.class == other.class &&
        length == other.length &&
        nodes.each_with_index.all? do |node, index|
          Node.wrap(node, context) == other[index]
        end
    end

    def text
      map(&:text).join
    end

    def remove
      each(&:remove)
      self
    end

    # Delete a node from the set
    # Accepts both wrapped Moxml nodes and native nodes
    def delete(node)
      # If it's a wrapped Moxml node, unwrap to native
      native_node = node.respond_to?(:native) ? node.native : node
      @nodes.delete(native_node)
      self
    end
  end
end
