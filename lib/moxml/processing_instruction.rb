# frozen_string_literal: true

module Moxml
  module ProcessingInstruction
    include Node

    def target
      adapter.processing_instruction_target(@native)
    end

    # A PI's DOM name is its target (Nokogiri semantics); defined
    # after target so the alias resolves at module load.
    def name
      target
    end

    def target=(new_target)
      adapter.set_node_name(@native, new_target.to_s)
    end

    # Returns the primary identifier for this processing instruction (its target)
    # @return [String] the PI target
    def identifier
      target
    end

    def content
      adapter.processing_instruction_content(@native)
    end

    def content=(new_content)
      adapter.set_processing_instruction_content(@native, new_content.to_s)
    end
  end
end
