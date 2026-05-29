# frozen_string_literal: true

module Moxml
  module Adapter
    class Libxml < Base
      # Restores configured character entities into explicit Moxml
      # EntityReference nodes after LibXML has parsed the native tree.
      class EntityRestorer
        def initialize(doc, adapter: Libxml)
          @doc = doc
          @ctx = doc.context
          @registry = @ctx.entity_registry
          @config = @ctx.config
          @adapter = adapter
        end

        def run
          return unless @registry && @doc.root

          walk(@doc.root)
        end

        private

        def walk(element)
          # Snapshot because we may add/remove siblings during the walk.
          element.children.to_a.each do |child|
            if child.is_a?(::Moxml::Text)
              restore_text_node(child)
            elsif child.is_a?(::Moxml::Element)
              walk(child)
            end
          end
        end

        # Matches DocumentBuilder's previous behavior, including the libxml
        # limitation that adjacent native text nodes get merged.
        def restore_text_node(text_node)
          content = text_node.content
          return unless content

          chunks = chunk_text(content)
          return if chunks.size == 1 && chunks.first.first == :text

          parent = text_node.parent
          return unless parent

          text_node.remove
          chunks.each { |type, payload| append_chunk(parent, type, payload) }
        end

        def chunk_text(content)
          chunks = []
          buffer = +""
          restorable = @registry.restorable_codepoints

          content.each_char do |char|
            cp = char.ord
            if restorable.include?(cp) &&
                (name = @registry.primary_name_for_codepoint(cp)) &&
                @registry.should_restore?(cp, config: @config)
              unless buffer.empty?
                chunks << [:text, buffer.dup]
                buffer.clear
              end
              chunks << [:eref, name]
            else
              buffer << char
            end
          end

          chunks << [:text, buffer.dup] unless buffer.empty?
          chunks
        end

        def append_chunk(parent, type, payload)
          case type
          when :text
            parent.add_child(::Moxml::Text.new(
                               @adapter.create_native_text(payload), @ctx
                             ))
          when :eref
            parent.add_child(
              ::Moxml::EntityReference.new(
                @adapter.create_native_entity_reference(payload),
                @ctx,
              ),
            )
          end
        end
      end
    end
  end
end
