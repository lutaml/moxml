# frozen_string_literal: true

require "openssl"
require "base64"

module Moxml
  # W3C XML Signature (xmldsig-core-1.1) processing for any moxml adapter.
  #
  # All XML operations flow through Moxml::Document / Moxml::Element; the
  # signature module never touches the underlying adapter (Nokogiri, Oga,
  # REXML, Ox, LibXML) directly.
  module Signature
    DSIG_NS = "http://www.w3.org/2000/09/xmldsig#"
    DSIG11_NS = "http://www.w3.org/2009/xmldsig11#"
    DSIG_MORE_NS = "http://www.w3.org/2001/04/xmldsig-more#"

    autoload :Error, "moxml/signature/errors"
    autoload :SignatureError, "moxml/signature/errors"
    autoload :UnknownAlgorithm, "moxml/signature/errors"
    autoload :DuplicateAlgorithm, "moxml/signature/errors"
    autoload :SigningError, "moxml/signature/errors"
    autoload :VerificationError, "moxml/signature/errors"
    autoload :ReferenceDigestMismatch, "moxml/signature/errors"
    autoload :SignatureValueMismatch, "moxml/signature/errors"
    autoload :TransformError, "moxml/signature/errors"
    autoload :CanonicalizationError, "moxml/signature/errors"
    autoload :MalformedSignatureError, "moxml/signature/errors"
    autoload :SignatureKeyError, "moxml/signature/errors"

    autoload :Algorithms, "moxml/signature/algorithms"
    autoload :C14n, "moxml/c14n"
    autoload :Model, "moxml/signature/model"
    autoload :Serializer, "moxml/signature/serializer"
    autoload :Parser, "moxml/signature/parser"
    autoload :ReferenceResolver, "moxml/signature/reference_resolver"
    autoload :Signer, "moxml/signature/signer"
    autoload :Verifier, "moxml/signature/verifier"
    autoload :KeyExtractor, "moxml/signature/key_extractor"
    autoload :TransformPipeline, "moxml/signature/transform_pipeline"
    autoload :VerificationResult, "moxml/signature/verification_result"
    autoload :SingleVerificationResult,
             "moxml/signature/single_verification_result"
    autoload :ReferenceResult, "moxml/signature/reference_result"

    class << self
      def sign(context:, document:, key:, **options)
        signature = build_signature(context: context, document: document, **options)
        Signer.new(
          context: context,
          signature: signature,
          document: document,
          key: key,
        ).sign
        signature
      end

      def verify(context:, document:, key: nil, **options)
        Verifier.new(context: context, document: document, key: key, **options).verify
      end

      private

      def build_signature(context:, document:, reference_uri:, signature_method:,
                          canonicalization_method:, digest_method:, transforms:,
                          key_info: nil, signature_id: nil, **)
        signed_info = Model::SignedInfo.new(
          canonicalization_method: Model::AlgorithmMethod.new(
            algorithm: canonicalization_method,
          ),
          signature_method: Model::AlgorithmMethod.new(
            algorithm: signature_method,
          ),
          references: [
            Model::Reference.new(
              uri: reference_uri,
              transforms: Model::Transforms.new(
                transforms: transforms.map do |t|
                  Model::Transform.new(algorithm: t)
                end,
              ),
              digest_method: Model::DigestMethod.new(algorithm: digest_method),
            ),
          ],
        )

        Model::Signature.new(
          id: signature_id,
          signed_info: signed_info,
          key_info: key_info,
        )
      end
    end
  end
end
