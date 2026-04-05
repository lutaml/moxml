# frozen_string_literal: true

module Moxml
  class Context
    attr_reader :config

    def initialize(adapter = nil)
      @config = Config.new(adapter)
    end

    def entity_registry
      @entity_registry ||= build_entity_registry
    end

    def create_document(native_doc = nil)
      Document.new(config.adapter.create_document(native_doc), self)
    end

    def parse(xml, options = {})
      # Detect if input has XML declaration
      xml_string = if xml.respond_to?(:read)
                     xml.read.tap do
                       xml.rewind if xml.respond_to?(:rewind)
                     end
                   else
                     xml.to_s
                   end
      has_declaration = xml_string.strip.start_with?("<?xml")

      # Parse with adapter, passing self (context) so adapter can use our config
      parsed_options = default_options.merge(options)
      doc = config.adapter.parse(xml_string, parsed_options, self)

      # Set declaration flag on Document wrapper (proper OOP)
      doc.has_xml_declaration = has_declaration if doc.is_a?(Document)

      doc
    end

    # Parse XML using SAX (event-driven) parsing
    #
    # SAX parsing is memory-efficient and suitable for large XML files.
    # Provide either a handler object or a block with DSL.
    #
    # @param xml [String, IO] XML string or IO object to parse
    # @param handler [Moxml::SAX::Handler, nil] Handler object (optional if block given)
    # @yield [block] DSL block for defining handlers (optional if handler given)
    # @return [void]
    # @raise [ArgumentError] if neither handler nor block is provided
    #
    # @example With handler object
    #   handler = MyHandler.new
    #   context.sax_parse(xml_string, handler)
    #
    # @example With block
    #   context.sax_parse(xml_string) do
    #     start_element { |name, attrs| puts name }
    #     characters { |text| puts text }
    #   end
    #
    def sax_parse(xml, handler = nil, &block)
      # Load SAX module if not already loaded
      require_relative "sax" unless defined?(Moxml::SAX)

      # Create block handler if block given
      handler ||= SAX::BlockHandler.new(&block) if block

      # Validate handler
      raise ArgumentError, "Handler or block required" unless handler
      unless handler.is_a?(SAX::Handler)
        raise ArgumentError, "Handler must inherit from Moxml::SAX::Handler"
      end

      # Delegate to adapter
      config.adapter.sax_parse(xml, handler)
    end

    private

    def build_entity_registry
      registry = EntityRegistry.new(
        mode: config.entity_load_mode,
        entity_provider: config.entity_provider,
      )
      config.preload_entity_sets.each do |set_name|
        case set_name
        when :html5 then registry.load_html5
        when :mathml then registry.load_mathml
        when :iso then registry.load_iso
        end
      end
      registry
    end

    def default_options
      {
        encoding: config.default_encoding,
        strict: config.strict_parsing,
        indent: config.default_indent,
      }
    end
  end
end
