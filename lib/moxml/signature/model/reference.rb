# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class Reference
        attr_accessor :id, :uri, :type, :transforms, :digest_method,
                      :digest_value

        def initialize(id: nil, uri: nil, type: nil, transforms: nil,
                       digest_method: nil, digest_value: nil)
          @id = id
          @uri = uri
          @type = type
          @transforms = transforms
          @digest_method = digest_method
          @digest_value = digest_value
        end
      end
    end
  end
end
