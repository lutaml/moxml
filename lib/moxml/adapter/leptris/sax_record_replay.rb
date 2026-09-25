# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      # Replays the engine's bulk SAX record table (leptris#1298) to
      # the bridge protocol. One drain crossing replaces the
      # per-event recorder replay; the only String materializations
      # left are the name/value/text data the handler actually
      # consumes. End events reconstruct from the records' parent
      # indices with a name-carrying stack — pre-order records make
      # a parent mismatch the exact close boundary, and
      # self-closing elements pop at their next sibling, matching
      # the callback engine's event stream.
      #
      # @private
      class SaxRecordReplay
        KIND_ELEMENT = ::Leptris::XML::SAX::Records::KIND_ELEMENT

        def initialize(bridge)
          @bridge = bridge
        end

        def run(table)
          @bridge.start_document
          idx_stack = []
          name_stack = []
          count = table.count
          i = 0
          while i < count
            while !idx_stack.empty? && table.parent(i) != idx_stack.last
              idx_stack.pop
              @bridge.end_element(name_stack.pop)
            end
            if table.kind(i) == KIND_ELEMENT
              name = table.view(i)
              pairs = []
              k = table.attr_first(i)
              last = k + table.attr_count_of(i)
              while k < last
                v = table.attr_value(k)
                pairs << [table.attr_name(k),
                          table.attr_value_has_ws?(k) ? v.tr("\t\n\r", " ") : v]
                k += 1
              end
              @bridge.start_element(name, pairs)
              idx_stack << i
              name_stack << name
            else
              @bridge.characters(table.view(i))
            end
            i += 1
          end
          @bridge.end_element(name_stack.pop) until name_stack.empty?
          @bridge.end_document
        end
      end
    end
  end
end
