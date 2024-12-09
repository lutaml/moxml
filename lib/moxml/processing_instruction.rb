module Moxml
  class ProcessingInstruction < Node
    def target
      adapter.processing_instruction_target(@native)
    end

    def target=(new_target)
      adapter.set_node_name(@native, new_target.to_s)
      self
    end

    def content
      adapter.processing_instruction_content(@native)
    end

    def content=(new_content)
      adapter.set_processing_instruction_content(@native, new_content.to_s)
      self
    end

    def processing_instruction?
      true
    end
  end
end
