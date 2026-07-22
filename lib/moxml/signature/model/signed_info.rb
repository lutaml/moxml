# frozen_string_literal: true

module Moxml
  module Signature
    module Model
      class SignedInfo
        attr_accessor :id, :canonicalization_method, :signature_method,
                      :references

        def initialize(id: nil, canonicalization_method: nil,
                       signature_method: nil, references: [])
          @id = id
          @canonicalization_method = canonicalization_method
          @signature_method = signature_method
          @references = references
        end
      end
    end
  end
end
