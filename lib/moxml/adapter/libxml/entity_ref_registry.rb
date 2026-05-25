# frozen_string_literal: true

module Moxml
  module Adapter
    class Libxml < Base
      # Tracks entity-reference insertions that cannot live in LibXML's native
      # node tree, plus the child sequence needed to serialize them in order.
      class EntityRefRegistry
        ENTITY_REFS_KEY = :_entity_ref_pairs
        CHILD_SEQUENCE_KEY = :_child_seq_pairs
        NON_WHITESPACE_RE = /\S/
        private_constant :ENTITY_REFS_KEY, :CHILD_SEQUENCE_KEY, :NON_WHITESPACE_RE

        def initialize(attachments, doc)
          @attachments = attachments
          @doc = doc
        end

        def active?
          @doc ? @attachments.key?(@doc, ENTITY_REFS_KEY) : false
        end

        def register(element, ref)
          return unless @doc && element

          path = path_for(element)

          refs_by_path = @attachments.get(@doc, ENTITY_REFS_KEY) || {}
          (refs_by_path[path] ||= []) << ref
          @attachments.set(@doc, ENTITY_REFS_KEY, refs_by_path)

          seq_by_path = @attachments.get(@doc, CHILD_SEQUENCE_KEY) || {}
          existing = seq_by_path[path]
          if existing
            existing << :eref
          else
            seq_by_path[path] = Array.new(count_native_children(element), :native)
            seq_by_path[path] << :eref
            @attachments.set(@doc, CHILD_SEQUENCE_KEY, seq_by_path)
          end
        end

        def append_native(element)
          return unless @doc && element

          seq_by_path = @attachments.get(@doc, CHILD_SEQUENCE_KEY)
          return unless seq_by_path

          seq = seq_by_path[path_for(element)]
          return unless seq

          seq << :native
        end

        def refs_for(element)
          return nil unless @doc && element

          refs_by_path = @attachments.get(@doc, ENTITY_REFS_KEY)
          refs_by_path && refs_by_path[path_for(element)]
        end

        def sequence_for(element)
          return nil unless @doc && element

          seq_by_path = @attachments.get(@doc, CHILD_SEQUENCE_KEY)
          seq_by_path && seq_by_path[path_for(element)]
        end

        def serialization_for(element)
          refs = refs_for(element)
          return [nil, nil] unless refs && !refs.empty?

          seq = sequence_for(element)
          return [nil, nil] unless seq

          [refs, seq]
        end

        private

        def path_for(element)
          element.path
        end

        def count_native_children(element)
          return 0 unless element.is_a?(::LibXML::XML::Node) && element.children?

          count = 0
          element.each_child do |child|
            count += 1 unless blank_text_node?(child)
          end
          count
        end

        def blank_text_node?(child)
          child.text? && blank_content?(child.content)
        end

        def blank_content?(content)
          content.nil? || !content.match?(NON_WHITESPACE_RE)
        end
      end
    end
  end
end
