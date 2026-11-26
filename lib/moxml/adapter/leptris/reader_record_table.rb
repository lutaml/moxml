# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      # The Reader's uniform record surface (#582 gap 4): one shape
      # over both sources — the engine's bulk drain table (the hot
      # path) and a callback-stream fallback for documents outside
      # the drain subset (the engine returns nil for those, e.g.
      # declaration-bearing documents). The Reader navigates depth
      # and subtree boundaries from parent indices; end markers are
      # synthesized, so the fallback records starts and text only.
      #
      # @private
      class ReaderRecordTable
        def self.open(xml_string)
          native = ::Leptris::XML::SAX::Records.open(xml_string)
          return new(native) if native

          build_from_callbacks(xml_string)
        end

        def self.build_from_callbacks(xml_string)
          rows = []
          stack = []
          handler = Object.new
          handler.define_singleton_method(:on_start_element) do |name, attr_hash, _ns_hash|
            attrs = (attr_hash || {}).map do |k, v|
              [k.to_s.dup, v.to_s.dup, v.match?(/[\t\n\r]/)]
            end
            rows << { element: true, view: name.dup,
                      parent: stack.last, attrs: attrs }
            stack.push(rows.size - 1)
          end
          handler.define_singleton_method(:on_end_element) do |_name|
            stack.pop
          end
          handler.define_singleton_method(:on_characters) do |text|
            unless text.empty?
              rows << { element: false, view: text.dup,
                        parent: stack.last, attrs: [] }
            end
          end
          %i[on_start_document on_end_document on_comment on_cdata
             on_processing_instruction on_error].each do |ignored|
            handler.define_singleton_method(ignored) do |*_args|
              # the Reader ignores lifecycle callbacks
            end
          end

          bridge = LeptrisSAXBridge.new(handler)
          ::Leptris::XML::SAX::Parser.new(bridge).parse(xml_string)
          new(CallbackTable.new(rows))
        end

        def initialize(native)
          @native = native
        end

        def count
          @native.count
        end

        def element?(index)
          if @native.is_a?(CallbackTable)
            @native.element?(index)
          else
            @native.kind(index) == ::Leptris::XML::SAX::Records::KIND_ELEMENT
          end
        end

        def view(index)
          @native.view(index)
        end

        def parent(index)
          @native.parent(index)
        end

        def attr_first(index)
          @native.attr_first(index)
        end

        def attr_count_of(index)
          @native.attr_count_of(index)
        end

        def attr_name(attr_index)
          @native.attr_name(attr_index)
        end

        def attr_value(attr_index)
          @native.attr_value(attr_index)
        end

        def attr_value_has_ws?(attr_index)
          @native.attr_value_has_ws?(attr_index)
        end

        def free
          @native.free
        end

        # The callback-stream table: same surface, Ruby rows.
        class CallbackTable
          attr_reader :rows

          def initialize(rows)
            @rows = rows
            @attr_offsets = []
            offset = 0
            @rows.each_with_index do |row, i|
              @attr_offsets[i] = offset
              offset += row[:attrs].size
            end
          end

          def count
            @rows.size
          end

          def element?(index)
            @rows[index][:element]
          end

          def view(index)
            @rows[index][:view]
          end

          def parent(index)
            @rows[index][:parent]
          end

          def attr_first(index)
            @attr_offsets[index]
          end

          def attr_count_of(index)
            @rows[index][:attrs].size
          end

          def attr_name(attr_index)
            flat_attrs[attr_index][0]
          end

          def attr_value(attr_index)
            flat_attrs[attr_index][1]
          end

          def attr_value_has_ws?(attr_index)
            flat_attrs[attr_index][2]
          end

          def free; end

          private

          def flat_attrs
            @flat_attrs ||= @rows.flat_map { |row| row[:attrs] }
          end
        end
      end
    end
  end
end
