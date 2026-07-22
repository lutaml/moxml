# frozen_string_literal: true

module Moxml
  module Signature
    # Plain-Ruby-Object model of the W3C ds:Signature schema.
    #
    # Models carry data; they do not (de)serialize themselves. The Serializer
    # walks a model and emits a Moxml document; the Parser walks a Moxml
    # document and constructs a model. This separation keeps the data shape
    # and the wire shape independent.
    module Model
      autoload :Signature, "moxml/signature/model/signature"
      autoload :SignedInfo, "moxml/signature/model/signed_info"
      autoload :Reference, "moxml/signature/model/reference"
      autoload :Transforms, "moxml/signature/model/transforms"
      autoload :Transform, "moxml/signature/model/transform"
      autoload :DigestMethod, "moxml/signature/model/digest_method"
      autoload :AlgorithmMethod, "moxml/signature/model/algorithm_method"
      autoload :SignatureValue, "moxml/signature/model/signature_value"
      autoload :KeyInfo, "moxml/signature/model/key_info"
      autoload :KeyValue, "moxml/signature/model/key_value"
      autoload :ObjectElement, "moxml/signature/model/object_element"
    end
  end
end
