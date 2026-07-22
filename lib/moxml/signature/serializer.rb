# frozen_string_literal: true

require "base64"

module Moxml
  module Signature
    # Translates a Model::Signature into a Moxml::Document.
    #
    # Output is a Moxml::Document whose root is <ds:Signature> in the
    # http://www.w3.org/2000/09/xmldsig# namespace. The caller attaches
    # the root to the target document.
    class Serializer
      attr_reader :context

      def initialize(context:)
        @context = context
      end

      def serialize(signature)
        doc = context.parse("<ds:Signature xmlns:ds=\"#{DSIG_NS}\"/>")
        root = doc.root
        root["Id"] = signature.id if signature.id

        if signature.signed_info
          root.add_child(serialize_signed_info_element(signature.signed_info).root)
        end
        if signature.signature_value
          root.add_child(serialize_signature_value(signature.signature_value).root)
        end
        if signature.key_info
          root.add_child(serialize_key_info(signature.key_info).root)
        end
        signature.objects.each do |obj|
          root.add_child(serialize_object(obj).root)
        end

        doc
      end

      # Produces a standalone ds:SignedInfo document. Used by Signer/Verifier
      # when canonicalizing SignedInfo in isolation (the spec requires
      # canonicalization over the SignedInfo element only).
      def serialize_signed_info(signed_info)
        doc = context.parse("<ds:SignedInfo xmlns:ds=\"#{DSIG_NS}\"/>")
        root = doc.root
        root["Id"] = signed_info.id if signed_info.id
        populate_signed_info(root, signed_info)
        doc
      end

      private

      def serialize_signed_info_element(signed_info)
        serialize_signed_info(signed_info)
      end

      def populate_signed_info(root, signed_info)
        if signed_info.canonicalization_method
          root.add_child(algorithm_element(root.document, "CanonicalizationMethod",
                                           signed_info.canonicalization_method).root)
        end
        if signed_info.signature_method
          root.add_child(algorithm_element(root.document, "SignatureMethod",
                                           signed_info.signature_method).root)
        end
        signed_info.references.each do |r|
          root.add_child(reference_element(root.document, r).root)
        end
      end

      def algorithm_element(doc, name, method)
        sub_doc = doc.context.parse("<ds:#{name} xmlns:ds=\"#{DSIG_NS}\" Algorithm=\"#{escape_attr(method.algorithm)}\"/>")
        if method.parameters.is_a?(Hash) && method.parameters[:hmac_output_length]
          len = sub_doc.root.document.create_element("HMACOutputLength")
          len.add_namespace("ds", DSIG_NS)
          len.namespace = { "ds" => DSIG_NS }
          len.add_child(len.document.create_text(method.parameters[:hmac_output_length].to_s))
          sub_doc.root.add_child(len)
        end
        sub_doc
      end

      def reference_element(doc, reference)
        sub_doc = doc.context.parse("<ds:Reference xmlns:ds=\"#{DSIG_NS}\"/>")
        el = sub_doc.root
        el["Id"] = reference.id if reference.id
        el["URI"] = reference.uri if reference.uri
        el["Type"] = reference.type if reference.type

        if reference.transforms && !reference.transforms.empty?
          tf = sub_doc.context.parse("<ds:Transforms xmlns:ds=\"#{DSIG_NS}\"/>").root
          reference.transforms.each do |t|
            tr = sub_doc.context.parse("<ds:Transform xmlns:ds=\"#{DSIG_NS}\" Algorithm=\"#{escape_attr(t.algorithm)}\"/>").root
            tf.add_child(tr)
          end
          el.add_child(tf)
        end

        if reference.digest_method
          dm = sub_doc.context.parse("<ds:DigestMethod xmlns:ds=\"#{DSIG_NS}\" Algorithm=\"#{escape_attr(reference.digest_method.algorithm)}\"/>").root
          el.add_child(dm)
        end

        dv = sub_doc.context.parse("<ds:DigestValue xmlns:ds=\"#{DSIG_NS}\"/>").root
        dv.add_child(dv.document.create_text(reference.digest_value || ""))
        el.add_child(dv)
        sub_doc
      end

      def serialize_signature_value(signature_value)
        doc = context.parse("<ds:SignatureValue xmlns:ds=\"#{DSIG_NS}\"/>")
        root = doc.root
        root["Id"] = signature_value.id if signature_value.id
        if signature_value.value
          encoded = Base64.strict_encode64(signature_value.value)
          root.add_child(doc.create_text(encoded))
        end
        doc
      end

      def serialize_key_info(key_info)
        doc = context.parse("<ds:KeyInfo xmlns:ds=\"#{DSIG_NS}\"/>")
        root = doc.root
        root["Id"] = key_info.id if key_info.id
        if key_info.key_name
          kn = context.parse("<ds:KeyName xmlns:ds=\"#{DSIG_NS}\"/>").root
          kn.add_child(doc.create_text(key_info.key_name))
          root.add_child(kn)
        end
        key_info.raw_elements.each { |e| root.add_child(e.dup) }
        doc
      end

      def serialize_object(obj)
        attrs = ""
        attrs << " Id=\"#{escape_attr(obj.id)}\"" if obj.id
        attrs << " MimeType=\"#{escape_attr(obj.mime_type)}\"" if obj.mime_type
        attrs << " Encoding=\"#{escape_attr(obj.encoding)}\"" if obj.encoding
        context.parse("<ds:Object xmlns:ds=\"#{DSIG_NS}\"#{attrs}/>")
        # Content rendering deferred: object payloads (Manifest, SignatureProperties,
        # XAdES QualifyingProperties) come in later tiers.
      end

      def escape_attr(value)
        value.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub("\"", "&quot;")
      end
    end
  end
end
