# frozen_string_literal: true

module Moxml
  module XPath
    # Document ordering for node-set results (TODO.sota/02, M3).
    #
    # XPath defines node-sets as unordered, but path-expression
    # results are conventionally in document order (and consumers
    # rely on it). Multi-step paths are evaluated by batching step N
    # over every step-(N-1) node, which concatenates subtree results
    # after sibling results — results must therefore be re-ordered.
    #
    # Ordering is a ONE-PASS position index per document, keyed by
    # native identity: `traverse` yields nodes in document order, and
    # the engines that re-order here (oga; the pure-Ruby XPath engine
    # lanes) expose stable native objects per node. The ancestry-walk
    # key (`key_for`) is quadratic on wide documents — every node
    # compares its way through its siblings' structural equality —
    # and is kept only as a fallback for natives the index does not
    # know (attribute results, unstable identities).
    module Ordering
      module_function

      INDEXED_ELEMENT_RANK = 1
      ATTRIBUTE_RANK = 0
      FALLBACK_RANK = 2

      # Below this result size the ancestry walk is cheaper than one
      # document traverse (the index only pays off on wide results).
      INDEX_THRESHOLD = 16

      # Sorts wrappers into document order. Attributes sort before
      # the children of their element (XPath attribute-then-child
      # ordering). Nodes the index cannot place keep their relative
      # position at the end (stable sort).
      def document_order(nodes)
        return nodes if nodes.size < 2

        indexed = if nodes.size < INDEX_THRESHOLD
                    nodes.each_with_index.map do |node, i|
                      [fallback_key(node), i, node]
                    end
                  else
                    positions = position_index(nodes.first)
                    nodes.each_with_index.map do |node, i|
                      [positions.fetch(node.native) { fallback_key(node) },
                       i, node]
                    end
                  end
        indexed.sort_by { |key, i, _| [key, i] }.map(&:last)
      end

      # native => [rank, position] for every node in document order.
      # compare_by_identity: the natives are the engine's own objects,
      # and native equality may be structural (Oga compares subtrees).
      def position_index(node)
        doc = node
        doc = doc.parent while doc && !doc.is_a?(Moxml::Document)
        return {}.compare_by_identity unless doc

        index = {}.compare_by_identity
        position = 0
        doc.traverse do |n|
          index[n.native] = [INDEXED_ELEMENT_RANK, position]
          position += 1
        end
        index
      end

      # Documents with unstable native wrappers (a fresh object per
      # access) fall back to the ancestry path: correct, and only the
      # answer for lanes whose engine already orders natively.
      def fallback_key(node)
        kind_rank = node.is_a?(Moxml::Attribute) ? ATTRIBUTE_RANK : FALLBACK_RANK
        [kind_rank, ancestry_path(node)]
      end

      # Attributes are not children of their element, so their
      # document position is the parent's; same-parent attributes
      # keep their relative order (stable sort). A parentless
      # attribute stays unplaceable.
      def ancestry_path(node)
        if node.is_a?(Moxml::Attribute)
          parent = node.parent
          return [2_000_000] unless parent

          return ancestry_path(parent)
        end

        path = []
        current = node
        while current && !current.is_a?(Moxml::Document)
          parent = current.parent
          break unless parent

          siblings = parent.children.to_a
          idx = siblings.index { |s| s.equal?(current) } ||
            siblings.index(current)
          return [2_000_000] if idx.nil?

          path.unshift(idx)
          current = parent
        end
        path
      end
    end
  end
end
