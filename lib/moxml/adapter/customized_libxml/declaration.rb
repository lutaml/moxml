# frozen_string_literal: true

module Moxml
  module Adapter
    module CustomizedLibxml
      # Wrapper for LibXML document declarations
      #
      # LibXML::XML::Document properties (version, encoding, standalone)
      # are read-only after creation. This wrapper allows mutation by
      # storing values internally and regenerating XML when needed.
      class Declaration
        attr_accessor :version, :encoding
        attr_reader :native

        def initialize(native_doc, version = nil, encoding = nil,
                       standalone = nil)
          @native = native_doc
          # Store explicit values - don't default from native_doc
          @version = version || native_doc.version || "1.0"
          # Only use encoding if explicitly provided, otherwise nil
          @encoding = encoding
          # Parse standalone value
          @standalone_value = case standalone
                              when "yes", true
                                true
                              when "no", false
                                false
                              end
        end

        def standalone
          return nil if @standalone_value.nil?

          @standalone_value ? "yes" : "no"
        end

        def standalone=(value)
          @standalone_value = case value
                              when "yes", true
                                true
                              when "no", false
                                false
                              when nil
                                nil
                              end
        end

        # Generate XML declaration string
        def to_xml
          output = "<?xml version=\"#{@version}\""
          if @encoding && !@encoding.empty?
            output << " encoding=\"#{@encoding}\""
          end
          # Include standalone attribute if explicitly set (true or false)
          unless @standalone_value.nil?
            output << " standalone=\"#{standalone}\""
          end
          output << "?>"
          output
        end

        private

        def extract_encoding(libxml_encoding)
          return nil unless libxml_encoding

          case libxml_encoding
          when ::LibXML::XML::Encoding::UTF_8
            "UTF-8"
          when ::LibXML::XML::Encoding::ISO_8859_1
            "ISO-8859-1"
          when ::LibXML::XML::Encoding::UTF_16LE
            "UTF-16LE"
          when ::LibXML::XML::Encoding::UTF_16BE
            "UTF-16BE"
          when ::LibXML::XML::Encoding::UCS_2
            "UCS-2"
          else
            "UTF-8"
          end
        end
      end
    end
  end
end
