# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML processing instruction nodes
      class ProcessingInstruction < Node
        # PI content in XML 1.0 §2.6 is verbatim — entity references are
        # not resolved by the parser and no escaping is required on
        # serialization. The libxml adapter's set_processing_instruction_content
        # uses new_pi (raw storage), and the parser delivers .content
        # verbatim, so the wrapper just emits it as-is.
        def to_xml
          target = @native.name
          content = @native.content
          if content && !content.empty?
            "<?#{target} #{content}?>"
          else
            "<?#{target}?>"
          end
        end
      end
    end
  end
end
