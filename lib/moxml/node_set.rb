# frozen_string_literal: true

module Moxml
  class NodeSet
    include Enumerable

    attr_reader :nodes, :context

    def initialize(nodes, context, parent_node = nil)
      @nodes = Array(nodes)
      @context = context
      @wrapped = Array.new(@nodes.size)
      @parent_node = parent_node
    end

    def each
      return to_enum(:each) unless block_given?

      @nodes.each_with_index do |node, i|
        @wrapped[i] ||= wrap_with_parent(node)
        yield @wrapped[i]
      end
      self
    end

    def [](index)
      case index
      when Integer
        actual = index.negative? ? @nodes.size + index : index
        return nil unless actual >= 0 && actual < @nodes.size

        @wrapped[actual] ||= wrap_with_parent(@nodes[actual])
      when Range
        self.class.new(@nodes[index], @context)
      end
    end

    def first(n = nil)
      if n.nil?
        @nodes.empty? ? nil : self[0]
      else
        n.times.filter_map { |i| self[i] }
      end
    end

    def last
      @nodes.empty? ? nil : self[@nodes.size - 1]
    end

    def empty?
      @nodes.empty?
    end

    def size
      @nodes.size
    end
    alias length size

    def to_a
      @nodes.each_with_index do |_node, i|
        @wrapped[i] ||= wrap_with_parent(@nodes[i])
      end
      @wrapped.compact
    end

    def +(other)
      self.class.new(@nodes + other.nodes, @context)
    end

    def <<(node)
      # If it's a wrapped Moxml node, unwrap to native before storing
      native_node = node.respond_to?(:native) ? node.native : node
      @nodes << native_node
      @wrapped << nil
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
      self.class.new(unique_natives, @context)
    end

    def ==(other)
      self.class == other.class &&
        length == other.length &&
        @nodes.each_with_index.all? do |_node, index|
          self[index] == other[index]
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
      idx = @nodes.index(native_node)
      if idx
        @nodes.delete_at(idx)
        @wrapped.delete_at(idx)
      else
        @nodes.delete(native_node)
      end
      self
    end

    private

    def wrap_with_parent(native_node)
      wrapped = Moxml::Node.wrap(native_node, @context)
      if @parent_node && wrapped
        wrapped.instance_variable_set(:@parent_node, @parent_node)
      end
      wrapped
    end
  end
end
