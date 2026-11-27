# frozen_string_literal: true

module Moxml
  # A multi-root build target (#584): sibling nodes accumulate on a
  # backing document without root validation — the DocumentFragment
  # contract. Serialization walks the children; the backing document
  # itself never serializes.
  #
  # Storage is unified on an optional scratch element parked in the
  # backing document: when a builder face accumulates markup (it
  # flushes into an element sink — every fragment child at once), the
  # tree path appends there too, so face-built and tree-built children
  # stay in one place regardless of interleaving.
  class Fragment
    attr_reader :document, :scratch

    def initialize(document, scratch: nil)
      @document = document
      @scratch = scratch
    end

    # The native node the builder face accumulates into: the scratch
    # element when parked, the backing document otherwise.
    def native
      @scratch ? @scratch.native : @document.native
    end

    def create_element(name)
      @document.create_element(name)
    end

    def create_text(content)
      @document.create_text(content)
    end

    def create_cdata(content)
      @document.create_cdata(content)
    end

    def create_comment(content)
      @document.create_comment(content)
    end

    def create_processing_instruction(target, content)
      @document.create_processing_instruction(target, content)
    end

    def create_entity_reference(name)
      @document.create_entity_reference(name)
    end

    def children
      @scratch ? @scratch.children : @document.children
    end

    # Appends a built node into the same storage the face flushes into.
    def add_child(node)
      if @scratch
        @scratch.add_child(node)
      else
        @document.add_child(node)
      end
      node
    end

    def to_xml(options = {})
      # The DocumentFragment contract the builder seam relies on
      # (nokogiri AS_XML): empty elements self-close. Callers override
      # with expand_empty: true when they want the document flavor.
      options = { expand_empty: false }.merge(options)
      children.map { |child| child.to_xml(options) }.join
    end
  end
end
