# frozen_string_literal: true

module Moxml
  # Streaming pull reader (#582 gap 4): Nokogiri::XML::Reader parity
  # for memory-conscious consumers — the walk visits start elements,
  # text, and synthesized end markers without materializing the
  # document tree. The stream rides the adapter's record face
  # (`reader_records`); engines without one raise
  # NotImplementedError (loud degradation, never a silent lane
  # change).
  #
  #   reader = Moxml::Reader.new(xml, :leptris)
  #   while reader.read
  #     if reader.node_type == Moxml::Reader::TYPE_ELEMENT &&
  #        reader.name == "book" && reader["id"] == "b1"
  #       subtree = reader.outer_xml
  #     end
  #   end
  #
  # Depth is the element nesting level (the root is 0). End markers
  # are synthesized from the records' parent indices — the stream's
  # pre-order with parents makes the close boundary exact.
  # empty_element? answers for elements the stream carries no
  # children for. outer_xml is reconstructed from the records (the
  # entity spelling may differ from the source bytes).
  class Reader
    # Nokogiri-compatible node type values.
    TYPE_ELEMENT = 1
    TYPE_TEXT = 3
    TYPE_END_ELEMENT = 15

    attr_reader :node_type, :name, :value, :node_depth

    def initialize(source, adapter_name = nil)
      @context = adapter_name ? Context.new(adapter_name) : Context.new
      @records = @context.config.adapter.reader_records(source)
      @index = -1
      @pending_end = nil
      @current_depth = 0
      @empty_element = false
      @node_type = nil
      @name = nil
      @value = nil
      @node_depth = 0
    end

    def read
      if @pending_end
        record_end(@pending_end)
        @pending_end = nil
        return self
      end

      @index += 1
      return nil if @index >= @records.count

      if @records.element?(@index)
        record_element(@index)
        # the element's last child closes it: chain the synthesized end
        @pending_end = @index if last_child_boundary?(@index)
      else
        record_text(@index)
        owner = @records.parent(@index)
        @pending_end = owner if last_child_boundary?(owner) &&
          !@records.element?(owner)
      end
      self
    end

    def attributes
      pairs = {}
      each_attribute do |attr_name, attr_value|
        pairs[attr_name] = attr_value
      end
      pairs
    end

    def [](attr_name)
      return nil unless @node_type == TYPE_ELEMENT

      pairs = attributes
      pairs[attr_name] || pairs[attr_name.to_s.split(":", 2)[1]]
    end

    def empty_element?
      @empty_element
    end

    def element?
      @node_type == TYPE_ELEMENT
    end

    def end_element?
      @node_type == TYPE_END_ELEMENT
    end

    def text?
      @node_type == TYPE_TEXT
    end

    # The current element's subtree, reconstructed from the stream.
    # The entity spelling may differ from the source bytes.
    def outer_xml
      return nil unless @node_type == TYPE_ELEMENT

      out = +""
      serialize_subtree(@index, out)
      out
    end

    private

    def record_element(index)
      @node_type = TYPE_ELEMENT
      @name = @records.view(index)
      @value = nil
      @node_depth = record_depth(index)
      @empty_element = !has_children?(index)
      @current_depth = @node_depth
    end

    def record_text(index)
      @node_type = TYPE_TEXT
      @name = nil
      @value = @records.view(index)
      @node_depth = record_depth(@records.parent(index)) + 1
      @empty_element = false
    end

    def record_end(index)
      @node_type = TYPE_END_ELEMENT
      @name = @records.view(index)
      @value = nil
      @node_depth = record_depth(index)
      @empty_element = false
    end

    def record_depth(index)
      depth = 0
      walk = index
      while (parent = @records.parent(walk))
        depth += 1
        walk = parent
      end
      depth
    end

    def has_children?(index)
      child_scan(index) { return true }
      false
    end

    def last_child_boundary?(index)
      # the deepest open element's next record is outside the subtree
      last = index
      scan = index + 1
      count = @records.count
      while scan < count && @records.parent(scan) &&
          inside_subtree?(index, scan)
        last = scan
        scan += 1
      end
      last == index
    end

    def inside_subtree?(root, index)
      walk = index
      while (parent = @records.parent(walk))
        return true if parent == root

        walk = parent
      end
      false
    end

    def each_attribute
      k = @records.attr_first(@index)
      last = k + @records.attr_count_of(@index)
      while k < last
        v = @records.attr_value(k)
        value = @records.attr_value_has_ws?(k) ? v.tr("\t\n\r", " ") : v
        yield @records.attr_name(k), value
        k += 1
      end
    end

    def child_scan(index)
      count = @records.count
      scan = index + 1
      while scan < count
        parent = @records.parent(scan)
        break if parent.nil?
        break unless inside_subtree?(index, scan)

        yield scan if parent == index
        scan += 1
      end
    end

    def serialize_subtree(index, out)
      if @records.element?(index)
        out << "<#{@records.view(index)}"
        each_attribute_on(index) do |name, value|
          out << %( #{name}=") << escape(value, true) << ?"
        end
        if has_children?(index)
          out << ">"
          child_scan(index) { |child| serialize_subtree(child, out) }
          out << "</#{@records.view(index)}>"
        else
          out << "/>"
        end
      else
        out << escape(@records.view(index), false)
      end
    end

    def each_attribute_on(index)
      k = @records.attr_first(index)
      last = k + @records.attr_count_of(index)
      while k < last
        v = @records.attr_value(k)
        value = @records.attr_value_has_ws?(k) ? v.tr("\t\n\r", " ") : v
        yield @records.attr_name(k), value
        k += 1
      end
    end

    def escape(text, attribute)
      escaped = text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      attribute ? escaped.gsub('"', "&quot;") : escaped
    end
  end
end
