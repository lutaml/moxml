# frozen_string_literal: true

module Moxml
  module C14n
    module Nodes
      # Processing Instruction node.
      class ProcessingInstructionNode < Node
        attr_reader :target, :data

        def initialize(target:, data: "")
          super()
          @target = target
          @data = data
        end

        def name
          target
        end

        def node_type
          :processing_instruction
        end

        def text_content
          ""
        end
      end
    end
  end
end
