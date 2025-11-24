# frozen_string_literal: true

require_relative "sax/handler"
require_relative "sax/element_handler"
require_relative "sax/block_handler"

module Moxml
  # SAX (Simple API for XML) parsing interface
  #
  # Provides event-driven XML parsing across all Moxml adapters.
  # SAX parsing is memory-efficient and suitable for processing large XML files.
  #
  # @example Class-based handler
  #   class MyHandler < Moxml::SAX::Handler
  #     def on_start_element(name, attributes = {}, namespaces = {})
  #       puts "Started element: #{name}"
  #     end
  #   end
  #
  #   context = Moxml.new
  #   context.sax_parse(xml_string, MyHandler.new)
  #
  # @example Block-based handler
  #   context.sax_parse(xml_string) do
  #     start_element { |name, attrs| puts "Element: #{name}" }
  #     characters { |text| puts "Text: #{text}" }
  #   end
  #
  module SAX
  end
end