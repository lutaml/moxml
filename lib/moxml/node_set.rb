# frozen_string_literal: true

module Moxml
  class NodeSet
    include Enumerable

    attr_reader :context

    # nodes: Array of natives, or an adapter's LazyNodeSet — the
    # native set is held unmaterialized until an operation needs an
    # Array (#+, #<<, #delete, Range slices).
    def initialize(nodes, context, parent_node = nil)
      @nodes = nodes.is_a?(Array) ? nodes : nil
      @lazy = @nodes ? nil : nodes
      @context = context
      @wrapped = Array.new(@nodes ? @nodes.size : @lazy.length)
      @parent_node = parent_node
    end

    # The raw native nodes — adapter-internal work only (issue #26).
    # The public surface is wrapper-only: every Enumerable access
    # goes through #each/#[]/#to_a, which wrap.
    def native_nodes
      return @nodes unless @nodes.nil?

      @nodes = @lazy.to_a
    end

    def each
      return to_enum(:each) unless block_given?

      wrapped = @wrapped
      index = 0
      (@nodes || @lazy).each do |node|
        wrapper = wrapped[index]
        unless wrapper
          wrapper = wrap_with_parent(node)
          wrapped[index] = wrapper
        end
        yield wrapper
        index += 1
      end
      self
    end

    def [](index)
      case index
      when Integer
        actual = index.negative? ? native_size + index : index
        return nil unless actual >= 0 && actual < native_size

        @wrapped[actual] ||= wrap_with_parent((@nodes || @lazy)[actual])
      when Range
        self.class.new(native_nodes[index], @context)
      end
    end

    def first(n = nil)
      if n.nil?
        native_size.zero? ? nil : self[0]
      else
        n.times.filter_map { |i| self[i] }
      end
    end

    def last
      native_size.zero? ? nil : self[native_size - 1]
    end

    def empty?
      native_size.zero?
    end

    def size
      native_size
    end
    alias length size

    def to_a
      i = 0
      (@nodes || @lazy).each do |node|
        @wrapped[i] ||= wrap_with_parent(node)
        i += 1
      end
      @wrapped.compact
    end

    def +(other)
      self.class.new(native_nodes + other.native_nodes, @context, @parent_node)
    end

    def <<(node)
      native_node = node.is_a?(Node) ? node.native : node
      native_nodes << native_node
      @wrapped << nil
      self
    end
    alias push <<

    # Deduplicate nodes based on native object identity
    # This is crucial for XPath operations like descendant-or-self
    # which may yield the same native node multiple times
    def uniq_by_native
      seen = {}
      unique_natives = native_nodes.select do |native|
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
        native_nodes.each_with_index.all? do |_node, index|
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
      native_node = node.is_a?(Node) ? node.native : node
      idx = native_nodes.index(native_node)
      if idx
        native_nodes.delete_at(idx)
        @wrapped.delete_at(idx)
      else
        native_nodes.delete(native_node)
      end
      self
    end

    private

    def native_size
      @nodes ? @nodes.size : @lazy.length
    end

    def wrap_with_parent(native_node)
      wrapped = Moxml::Node.wrap(native_node, @context)
      if @parent_node && wrapped
        wrapped.parent_node = @parent_node
      end
      wrapped
    end
  end
end
