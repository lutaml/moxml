# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class ObjectElement
        attr_accessor :id, :mime_type, :encoding, :content

        def initialize(id: nil, mime_type: nil, encoding: nil, content: nil)
          @id = id
          @mime_type = mime_type
          @encoding = encoding
          @content = content
        end
      end
    end
  end
end
