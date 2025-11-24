# frozen_string_literal: true

require_relative "handler"

module Moxml
  module SAX
    # Block-based SAX handler with DSL
    #
    # Provides a convenient block-based API for simple SAX parsing cases
    # without requiring a full class definition.
    #
    # @example Block-based parsing
    #   context.sax_parse(xml) do
    #     start_element { |name, attrs| puts "Element: #{name}" }
    #     characters { |text| puts "Text: #{text}" }
    #     end_element { |name| puts "End: #{name}" }
    #   end
    #
    # @example With instance variables
    #   books = []
    #   context.sax_parse(xml) do
    #     start_element do |name, attrs|
    #       books << { id: attrs["id"] } if name == "book"
    #     end
    #   end
    #
    class BlockHandler < Handler
      # Create a new block handler
      #
      # @param block [Proc] Block containing DSL calls
      # @yield DSL context for defining handlers
      def initialize(&block)
        super()
        @handlers = {}
        instance_eval(&block) if block
      end

      # Define handler for document start event
      #
      # @yield Block to execute when document parsing begins
      # @yieldreturn [void]
      # @return [void]
      def start_document(&block)
        @handlers[:start_document] = block
      end

      # Define handler for document end event
      #
      # @yield Block to execute when document parsing completes
      # @yieldreturn [void]
      # @return [void]
      def end_document(&block)
        @handlers[:end_document] = block
      end

      # Define handler for element start event
      #
      # @yield Block to execute when opening tag is encountered
      # @yieldparam name [String] Element name
      # @yieldparam attributes [Hash<String, String>] Element attributes
      # @yieldparam namespaces [Hash<String, String>] Namespace declarations
      # @yieldreturn [void]
      # @return [void]
      def start_element(&block)
        @handlers[:start_element] = block
      end

      # Define handler for element end event
      #
      # @yield Block to execute when closing tag is encountered
      # @yieldparam name [String] Element name
      # @yieldreturn [void]
      # @return [void]
      def end_element(&block)
        @handlers[:end_element] = block
      end

      # Define handler for character data event
      #
      # @yield Block to execute when character data is encountered
      # @yieldparam text [String] Character data
      # @yieldreturn [void]
      # @return [void]
      def characters(&block)
        @handlers[:characters] = block
      end

      # Define handler for CDATA section event
      #
      # @yield Block to execute when CDATA section is encountered
      # @yieldparam text [String] CDATA content
      # @yieldreturn [void]
      # @return [void]
      def cdata(&block)
        @handlers[:cdata] = block
      end

      # Define handler for comment event
      #
      # @yield Block to execute when comment is encountered
      # @yieldparam text [String] Comment content
      # @yieldreturn [void]
      # @return [void]
      def comment(&block)
        @handlers[:comment] = block
      end

      # Define handler for processing instruction event
      #
      # @yield Block to execute when PI is encountered
      # @yieldparam target [String] PI target
      # @yieldparam data [String] PI data
      # @yieldreturn [void]
      # @return [void]
      def processing_instruction(&block)
        @handlers[:processing_instruction] = block
      end

      # Define handler for error event
      #
      # @yield Block to execute when error occurs
      # @yieldparam error [Moxml::ParseError] The error
      # @yieldreturn [void]
      # @return [void]
      def error(&block)
        @handlers[:error] = block
      end

      # Define handler for warning event
      #
      # @yield Block to execute when warning occurs
      # @yieldparam message [String] Warning message
      # @yieldreturn [void]
      # @return [void]
      def warning(&block)
        @handlers[:warning] = block
      end

      # @private
      def on_start_document
        @handlers[:start_document]&.call
      end

      # @private
      def on_end_document
        @handlers[:end_document]&.call
      end

      # @private
      def on_start_element(name, attributes = {}, namespaces = {})
        @handlers[:start_element]&.call(name, attributes, namespaces)
      end

      # @private
      def on_end_element(name)
        @handlers[:end_element]&.call(name)
      end

      # @private
      def on_characters(text)
        @handlers[:characters]&.call(text)
      end

      # @private
      def on_cdata(text)
        @handlers[:cdata]&.call(text)
      end

      # @private
      def on_comment(text)
        @handlers[:comment]&.call(text)
      end

      # @private
      def on_processing_instruction(target, data)
        @handlers[:processing_instruction]&.call(target, data)
      end

      # @private
      def on_error(error)
        if @handlers[:error]
          @handlers[:error].call(error)
        else
          super
        end
      end

      # @private
      def on_warning(message)
        @handlers[:warning]&.call(message)
      end
    end
  end
end
