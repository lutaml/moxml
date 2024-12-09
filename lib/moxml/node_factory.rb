module Moxml
  class NodeFactory
    def self.create(type, context, *args)
      node_class = case type
        when :element then Element
        when :text then Text
        when :cdata then Cdata
        when :comment then Comment
        when :processing_instruction then ProcessingInstruction
        when :declaration then Declaration
        when :doctype then Doctype
        else
          raise ArgumentError, "Unknown node type: #{type}"
        end
      node_class.new(*args, context)
    end
  end
end
