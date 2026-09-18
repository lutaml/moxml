# frozen_string_literal: true

module Moxml
  # Plan-compiled materialization: declare the document shape once,
  # execute it against the adapter's bulk row stream — no wrapper
  # tree, no NodeSet, no per-node contract dispatch. The compiled
  # grammar instead of the interpreted walk.
  #
  #   plan = Moxml::Plan.new do
  #     on("record") { |attrs, _text, fields| Record.new(attrs["id"], attrs["kind"], fields) }
  #     on("field")  { |attrs, text, _kids| Field.new(attrs["name"], attrs["unit"], text) }
  #   end
  #   records = plan.parse(xml, ctx)
  #
  # Handlers run bottom-up as each element completes; +children+ is
  # the array of handler values for matched child elements whose
  # parent ALSO matched (values of unmatched parents are dropped —
  # matching a parent is the consumer's decision to keep a subtree).
  # +attrs+ is a Hash of the element's attributes (local name =>
  # value); +text+ is the first text child's content, or nil.
  #
  # Name matching is global (flat table, not path-relative): element
  # names unique per role — the dominant consumer shape — work as-is;
  # distinct roles sharing a name need distinct documents or a
  # rename upstream.
  #
  # Adapters with a bulk stream answer plan_rows (leptris: the
  # engine's one-pass C snapshot — pre-order, first-text on the
  # row); the rest run the generic pre-order wrapper walk below,
  # emitting the identical stream — spec-pinned equal.
  class Plan
    def initialize(&block)
      @handlers = {}
      instance_eval(&block) if block
    end

    # Registers a handler for elements named +name+ (local name).
    # Returns self so registrations chain.
    def on(name, &handler)
      raise ArgumentError, "on(#{name.inspect}) requires a block" unless handler

      @handlers[name] = handler
      self
    end

    # Parses +xml+ and materializes the plan against it.
    def parse(xml, context)
      materialize(context.parse(xml))
    end

    # Materializes the plan against a document (or element) wrapper.
    # Returns the values of top-level matched elements.
    def materialize(node)
      results = []
      frames = []   # per open depth: children values (nil = unmatched)
      meta = []     # per open depth: [name, attrs, text] (nil = unmatched)

      close_top = lambda do
        m = meta.pop
        children = frames.pop
        next unless m

        value = @handlers[m[0]].call(m[1], m[2], children)
        if frames.empty? || frames.last.nil?
          results << value
        else
          frames.last << value
        end
      end

      row = lambda do |name, attrs_pairs, text, depth|
        close_top.call while frames.size > depth
        handler = @handlers[name]
        if handler
          attrs = {}
          i = 0
          while i < attrs_pairs.length
            attrs[attrs_pairs[i]] = attrs_pairs[i + 1]
            i += 2
          end
          frames << []
          meta << [name, attrs, text]
        else
          frames << nil
          meta << nil
        end
      end

      adapter = node.context.config.adapter
      ran = adapter.plan_rows(node.native) do |name, pairs, text, depth|
        row.call(name, pairs, text, depth)
      end
      unless ran
        walk_wrappers(node) do |name, pairs, text, depth|
          row.call(name, pairs, text, depth)
        end
      end

      close_top.call while meta.any?
      results
    end

    private

    # Generic pre-order walk over the wrapper tree — the fallback
    # stream for adapters without a bulk path. Same protocol as
    # plan_rows: |name, attrs_pairs (flat [k, v, ...]), first-text,
    # depth|.
    def walk_wrappers(node, depth = 0)
      case node
      when Document
        (root = node.root) && walk_wrappers(root, depth) { |*a| yield(*a) }
      when Element
        first_text = nil
        node.children.each do |child|
          first_text ||= child.content if child.is_a?(Text)
        end
        yield(node.name, attribute_pairs(node), first_text, depth)
        node.children.each do |child|
          walk_wrappers(child, depth + 1) { |*a| yield(*a) } if child.is_a?(Element)
        end
      end
    end

    def attribute_pairs(element)
      pairs = []
      element.attributes.each do |attr|
        pairs << attr.name << attr.value
      end
      pairs
    end
  end
end
