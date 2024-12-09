require_relative "../xml_utils"
require_relative "../document_builder"

module Moxml
  module Adapter
    class Base
      # include XmlUtils

      class << self
        include XmlUtils

        def set_root(doc, element)
          raise NotImplementedError
        end

        def parse(xml, options = {})
          raise NotImplementedError
        end

        def create_document
          raise NotImplementedError
        end

        def create_element(name)
          validate_name(name)
          create_native_element(name)
        end

        def create_text(content)
          create_native_text(normalize_xml_value(content))
        end

        def create_cdata(content)
          create_native_cdata(normalize_xml_value(content))
        end

        def create_comment(content)
          create_native_comment(normalize_xml_value(content))
        end

        def create_doctype(name, external_id, system_id)
          create_native_doctype(name, external_id, system_id)
        end

        def create_processing_instruction(target, content)
          validate_name(target)
          create_native_processing_instruction(target, normalize_xml_value(content))
        end

        def create_declaration(version = "1.0", encoding = "UTF-8", standalone = nil)
          validate_declaration_version(version)
          validate_declaration_encoding(encoding)
          validate_declaration_standalone(standalone)
          create_native_declaration(version, encoding, standalone)
        end

        def create_namespace(element, prefix, uri)
          validate_prefix(prefix) if prefix
          validate_uri(uri)
          create_native_namespace(element, prefix, uri)
        end

        def validate_declaration_version(version)
          unless ::Moxml::Declaration::ALLOWED_VERSIONS.include?(version)
            raise ValidationError, "Invalid XML version: #{version}"
          end
        end

        def validate_declaration_encoding(encoding)
          return if encoding.nil?
          begin
            Encoding.find(encoding)
          rescue ArgumentError
            raise ValidationError, "Invalid encoding: #{encoding}"
          end
        end

        def validate_declaration_standalone(standalone)
          return if standalone.nil?
          unless ::Moxml::Declaration::ALLOWED_STANDALONE.include?(standalone)
            raise ValidationError, "Invalid standalone value: #{standalone}"
          end
        end

        protected

        def create_native_element(name)
          raise NotImplementedError
        end

        def create_native_text(content)
          raise NotImplementedError
        end

        def create_native_cdata(content)
          raise NotImplementedError
        end

        def create_native_comment(content)
          raise NotImplementedError
        end

        def create_native_doctype(name, external_id, system_id)
          raise NotImplementedError
        end

        def create_native_processing_instruction(target, content)
          raise NotImplementedError
        end

        def create_native_declaration(version, encoding, standalone)
          raise NotImplementedError
        end

        def create_native_namespace(element, prefix, uri)
          raise NotImplementedError
        end

        private

        def validate_prefix(prefix)
          unless prefix.match?(/\A[a-zA-Z_][\w\-]*\z/)
            raise ValidationError, "Invalid namespace prefix: #{prefix}"
          end
        end
      end
    end
  end
end
