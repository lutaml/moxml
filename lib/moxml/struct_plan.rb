# frozen_string_literal: true

module Moxml
  # Struct-compiled materialization — the fully compiled grammar:
  # declare the document shape once as STRUCTS; adapters with a C
  # executor (leptris 1.9.201.1+, the varargs-mint fix) mint the typed
  # with zero Ruby frames per element; everything else falls back to
  # an equivalent Moxml::Plan over the row stream (spec-pinned
  # equal).
  #
  #   plan = Moxml::StructPlan.new do
  #     element "record", Record, attrs: { "id" => :id, "kind" => :kind },
  #            children: :fields
  #     element "field", Field, attrs: { "name" => :name, "unit" => :unit },
  #            text: :value
  #   end
  #   records = plan.parse(xml, ctx)   # Array of Record
  #
  # Slot symbols must be the Struct's member names. Semantics equal
  # Moxml::Plan: unmatched elements are barriers — their matched
  # descendants surface at top level.
  class StructPlan
    Element = Struct.new(:klass, :attrs, :text, :children)

    def initialize(&block)
      @elements = {}
      instance_eval(&block) if block
    end

    # Registers a struct element. +attrs+ maps attribute names to
    # member slots; +text+ and +children+ name the member slots
    # receiving the first text child and the matched children array.
    # Returns self so registrations chain.
    def element(name, klass, attrs: {}, text: nil, children: nil)
      @elements[name] = Element.new(klass, attrs, text, children)
      self
    end

    # The compiled spec the C executor consumes:
    # {name => [klass, attrs, text slot, children slot]}. Slots
    # resolve to member INDICES once — the C executor's Integer
    # key path then writes by index, skipping the per-write member
    # name scan.
    def compile
      @elements.each_with_object({}) do |(name, el), spec|
        members = el.klass.members
        spec[name] = [
          el.klass,
          el.attrs.each_with_object({}) { |(a, slot), h| h[a] = members.index(slot) || slot },
          members.index(el.text) || el.text,
          members.index(el.children) || el.children,
        ]
      end
    end

    def parse(xml, context)
      materialize(context.parse(xml))
    end

    def materialize(node)
      adapter = node.context.config.adapter
      roots = adapter.plan_structs(node.native, compile)
      return roots if roots

      plan.materialize(node)
    end

    private

    # The fallback: the same element table as block handlers over
    # the plan row stream. instance_eval'd DSL — capture the table
    # in a local (the Plan's self has no @elements).
    def plan
      @plan ||= begin
        elements = @elements
        Moxml::Plan.new do
          elements.each do |name, el|
            on(name) do |attrs, text, children|
              obj = el.klass.new
              el.attrs.each { |aname, slot| obj[slot] = attrs[aname] }
              obj[el.text] = text if el.text
              obj[el.children] = children if el.children
              obj
            end
          end
        end
      end
    end
  end
end
