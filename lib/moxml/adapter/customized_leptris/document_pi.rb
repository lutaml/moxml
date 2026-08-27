# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLeptris
      # Document-level processing instruction. libleptris stores these
      # outside the element tree (a flat, document-ordered list with no
      # prolog/epilog anchoring — its serializer emits them all before
      # the root), reachable through Document#processing_instructions
      # as [target, data] pairs. This pseudo-native gives the pairs a
      # node identity so the moxml contract can list them as document
      # children.
      class DocumentPI
        attr_accessor :target, :data, :parent_doc
        alias content data
        alias content= data=

        def initialize(target, data = "", parent_doc = nil)
          @target = target
          @data = data.to_s
          @parent_doc = parent_doc
        end

        def to_xml
          data.empty? ? "<?#{target}?>" : "<?#{target} #{data}?>"
        end

        def ==(other)
          other.is_a?(self.class) && target == other.target && data == other.data
        end
      end
    end
  end
end
