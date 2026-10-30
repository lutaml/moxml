# frozen_string_literal: true

# Lifecycle record: the :libxml adapter is deprecated (#491); this wrapper dies with it.

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML processing instruction nodes
      class ProcessingInstruction < Node
        # XML 1.0 §2.6: PI content is verbatim — no entity resolution, no escaping.
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
