# frozen_string_literal: true

module Moxml
  module SAX
    # Abstract base class for SAX event handlers
    #
    # This class defines the interface for handling SAX parsing events.
    # Subclass this and override the event methods you need to handle.
    #
    # All event methods have default implementations that do nothing,
    # so you only need to override the events you care about.
    #
    # @example Create a custom handler
    #   class BookHandler < Moxml::SAX::Handler
    #     def on_start_element(name, attributes = {}, namespaces = {})
    #       puts "Found element: #{name}"
    #     end
    #   end
    #
    class Handler
      # Called when parsing begins
      #
      # @return [void]
      def on_start_document
        # Override in subclass if needed
      end

      # Called when parsing completes successfully
      #
      # @return [void]
      def on_end_document
        # Override in subclass if needed
      end

      # Called when an opening tag is encountered
      #
      # @param name [String] Element name (with namespace prefix if present)
      # @param attributes [Hash<String, String>] Element attributes
      # @param namespaces [Hash<String, String>] Namespace declarations on this element
      # @return [void]
      def on_start_element(name, attributes = {}, namespaces = {})
        # Override in subclass if needed
      end

      # Called when a closing tag is encountered
      #
      # @param name [String] Element name
      # @return [void]
      def on_end_element(name)
        # Override in subclass if needed
      end

      # Called when character data is encountered
      #
      # Note: This may be called multiple times for a single text node
      # if the parser breaks it into chunks. Concatenate if needed.
      #
      # @param text [String] Character data
      # @return [void]
      def on_characters(text)
        # Override in subclass if needed
      end

      # Called when a CDATA section is encountered
      #
      # @param text [String] CDATA content
      # @return [void]
      def on_cdata(text)
        # Override in subclass if needed
      end

      # Called when a comment is encountered
      #
      # @param text [String] Comment content
      # @return [void]
      def on_comment(text)
        # Override in subclass if needed
      end

      # Called when a processing instruction is encountered
      #
      # @param target [String] PI target
      # @param data [String] PI data/content
      # @return [void]
      def on_processing_instruction(target, data)
        # Override in subclass if needed
      end

      # Called when a fatal parsing error occurs
      #
      # Default implementation raises the error.
      # Override to handle errors differently.
      #
      # @param error [Moxml::ParseError] The parsing error
      # @return [void]
      # @raise [Moxml::ParseError] By default
      def on_error(error)
        raise error
      end

      # Called when a non-fatal warning occurs
      #
      # Default implementation ignores warnings.
      # Override to handle warnings (e.g., log them).
      #
      # @param message [String] Warning message
      # @return [void]
      def on_warning(message)
        # Override in subclass if needed
      end
    end
  end
end
