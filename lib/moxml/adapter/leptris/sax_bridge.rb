# frozen_string_literal: true

module Moxml
  module Adapter
    class Leptris
      # Bridge between the leptris SAX callbacks and Moxml::SAX::Handler.
      #
      # @private
      class LeptrisSAXBridge < ::Leptris::XML::SAX::Document
        include Moxml::SAX::NamespaceSplitter

        def initialize(handler)
          @handler = handler
          super()
        end

        def start_document
          @handler.on_start_document
        end

        def end_document
          @handler.on_end_document
        end

        def start_element(name, attrs = [])
          attr_hash, ns_hash = split_attributes_and_namespaces(attrs)
          @handler.on_start_element(name, attr_hash, ns_hash)
        end

        def end_element(name)
          @handler.on_end_element(name)
        end

        def characters(string)
          @handler.on_characters(string)
        end

        def comment(string)
          @handler.on_comment(string)
        end

        def cdata_block(string)
          @handler.on_cdata(string)
        end

        def processing_instruction(name, content)
          @handler.on_processing_instruction(name, content || "")
        end

        def error(message, _line = 0, _column = 0)
          @handler.on_error(Moxml::ParseError.new(message))
        end
      end
    end
  end
end
