# frozen_string_literal: true

require "base64"

module Moxml
  module Signature
    # Translates a Model::Signature into a Moxml::Document.
    #
    # All XML construction goes through moxml primitives
    # (create_element, []=, add_child, create_text). No string templates,
    # no manual attribute escaping — moxml handles entity encoding
    # correctly per the XML spec.
    class Serializer
      DS_PREFIX = "ds"

      attr_reader :context

      def initialize(context:)
        @context = context
      end

      def serialize(signature)
        doc = context.create_document
        root = create_namespaced_element("Signature", doc)
        root["Id"] = signature.id if signature.id
        doc.root = root

        if signature.signed_info
          root.add_child(build_signed_info(signature.signed_info, doc))
        end
        if signature.signature_value
          root.add_child(build_signature_value(signature.signature_value, doc))
        end
        if signature.key_info
          root.add_child(build_key_info(signature.key_info, doc))
        end
        signature.objects.each do |obj|
          root.add_child(build_object(obj, doc))
        end

        doc
      end

      # Produces a standalone ds:SignedInfo document. Used by the Signer
      # when canonicalizing SignedInfo in isolation.
      def serialize_signed_info(signed_info)
        doc = context.create_document
        root = create_namespaced_element("SignedInfo", doc)
        root["Id"] = signed_info.id if signed_info.id
        doc.root = root
        populate_signed_info(root, signed_info, doc)
        doc
      end

      private

      def build_signed_info(signed_info, doc)
        el = create_namespaced_element("SignedInfo", doc)
        el["Id"] = signed_info.id if signed_info.id
        populate_signed_info(el, signed_info, doc)
        el
      end

      def populate_signed_info(root, signed_info, doc)
        if signed_info.canonicalization_method
          root.add_child(
            build_algorithm_method("CanonicalizationMethod",
                                   signed_info.canonicalization_method, doc),
          )
        end
        if signed_info.signature_method
          root.add_child(
            build_algorithm_method("SignatureMethod",
                                   signed_info.signature_method, doc),
          )
        end
        signed_info.references.each do |ref|
          root.add_child(build_reference(ref, doc))
        end
      end

      def build_algorithm_method(name, method, doc)
        el = create_namespaced_element(name, doc)
        el["Algorithm"] = method.algorithm
        if method.parameters.is_a?(Hash) && method.parameters[:hmac_output_length]
          len = create_namespaced_element("HMACOutputLength", doc)
          len.add_child(doc.create_text(method.parameters[:hmac_output_length].to_s))
          el.add_child(len)
        end
        el
      end

      def build_reference(reference, doc)
        el = create_namespaced_element("Reference", doc)
        el["Id"] = reference.id if reference.id
        el["URI"] = reference.uri if reference.uri
        el["Type"] = reference.type if reference.type

        if reference.transforms && !reference.transforms.empty?
          tf = create_namespaced_element("Transforms", doc)
          reference.transforms.each do |transform|
            tr = create_namespaced_element("Transform", doc)
            tr["Algorithm"] = transform.algorithm
            tf.add_child(tr)
          end
          el.add_child(tf)
        end

        if reference.digest_method
          dm = create_namespaced_element("DigestMethod", doc)
          dm["Algorithm"] = reference.digest_method.algorithm
          el.add_child(dm)
        end

        dv = create_namespaced_element("DigestValue", doc)
        dv.add_child(doc.create_text(reference.digest_value || ""))
        el.add_child(dv)
        el
      end

      def build_signature_value(signature_value, doc)
        el = create_namespaced_element("SignatureValue", doc)
        el["Id"] = signature_value.id if signature_value.id
        if signature_value.value
          el.add_child(doc.create_text(Base64.strict_encode64(signature_value.value)))
        end
        el
      end

      def build_key_info(key_info, doc)
        el = create_namespaced_element("KeyInfo", doc)
        el["Id"] = key_info.id if key_info.id
        if key_info.key_name
          kn = create_namespaced_element("KeyName", doc)
          kn.add_child(doc.create_text(key_info.key_name))
          el.add_child(kn)
        end
        key_info.raw_elements.each { |raw| el.add_child(raw.dup) }
        el
      end

      def build_object(obj, doc)
        el = create_namespaced_element("Object", doc)
        el["Id"] = obj.id if obj.id
        el["MimeType"] = obj.mime_type if obj.mime_type
        el["Encoding"] = obj.encoding if obj.encoding
        # Payload content (Manifest, SignatureProperties, XAdES
        # QualifyingProperties) comes in later tiers.
        el
      end

      # Create an element in the xmldsig# namespace with the conventional
      # `ds` prefix. The namespace declaration is added once on the
      # element itself; descendants inherit it.
      def create_namespaced_element(local_name, doc)
        el = doc.create_element(local_name)
        el.add_namespace(DS_PREFIX, DSIG_NS)
        el.namespace = { DS_PREFIX => DSIG_NS }
        el
      end
    end
  end
end
