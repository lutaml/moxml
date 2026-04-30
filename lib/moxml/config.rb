# frozen_string_literal: true

module Moxml
  class Config
    VALID_ADAPTERS = %i[nokogiri oga rexml ox headed_ox libxml].freeze
    DEFAULT_ADAPTER = :nokogiri
    OPAL_DEFAULT_ADAPTER = :oga

    # Entity loading modes:
    # - :required - Must load entities, raise error if unavailable (default)
    # - :optional - Try to load, continue silently if unavailable
    # - :disabled - Don't load entities, use empty registry
    # - :custom - Use custom entity provider via entity_provider callback
    ENTITY_LOAD_MODES = %i[required optional disabled custom].freeze

    class << self
      attr_writer :default_adapter

      def default
        @default ||= new(default_adapter, true, "UTF-8")
      end

      def default_adapter
        @default_adapter || runtime_default_adapter
      end

      def runtime_default_adapter
        return OPAL_DEFAULT_ADAPTER if RUBY_ENGINE == "opal"

        detect_loaded_adapter || DEFAULT_ADAPTER
      end

      def detect_loaded_adapter
        return :nokogiri if Object.const_defined?(:Nokogiri)
        return :ox if Object.const_defined?(:Ox)
        return :oga if Object.const_defined?(:Oga)

        nil
      end
    end

    NAMESPACE_VALIDATION_MODES = %i[strict lenient].freeze

    # Entity restoration modes:
    # - :lenient (default) — restore any known entity from the registry
    # - :strict — only restore DTD-declared entities (falls back to lenient until DTD parsing is implemented)
    ENTITY_RESTORATION_MODES = %i[strict lenient].freeze

    attr_reader :adapter_name
    attr_accessor :strict_parsing,
                  :default_encoding,
                  :entity_encoding,
                  :default_indent,
                  :restore_entities,
                  :preload_entity_sets,
                  :entity_load_mode,
                  :entity_provider,
                  :namespace_validation_mode,
                  :entity_restoration_mode

    def initialize(adapter_name = nil, strict_parsing = nil,
                   default_encoding = nil)
      self.adapter = adapter_name || Config.default.adapter_name
      @strict_parsing = strict_parsing || Config.default.strict_parsing
      @default_encoding = default_encoding || Config.default.default_encoding
      # reserved for future use
      @default_indent = 2
      @entity_encoding = :basic
      @restore_entities = false
      @preload_entity_sets = []
      @entity_load_mode = :required
      @entity_provider = nil
      @namespace_validation_mode = :strict
      @entity_restoration_mode = :lenient
    end

    def adapter=(name)
      name = name.to_sym
      @adapter = nil

      unless VALID_ADAPTERS.include?(name)
        raise Moxml::AdapterError.new(
          "Invalid adapter: #{name}",
          adapter: name,
          operation: "set_adapter",
        )
      end

      @adapter_name = name
      adapter
    end

    def default_adapter=(name)
      self.adapter = name
      self.class.default_adapter = name
    end

    def adapter
      @adapter ||= Adapter.load(@adapter_name)
    end

    def entity_load_mode=(mode)
      unless ENTITY_LOAD_MODES.include?(mode)
        raise ArgumentError,
              "Invalid entity_load_mode: #{mode}. Must be one of: #{ENTITY_LOAD_MODES.join(', ')}"
      end

      @entity_load_mode = mode
    end

    def namespace_validation_mode=(mode)
      mode = mode.to_sym
      unless NAMESPACE_VALIDATION_MODES.include?(mode)
        raise ArgumentError,
              "Invalid namespace_validation_mode: #{mode}. Must be one of: #{NAMESPACE_VALIDATION_MODES.join(', ')}"
      end

      @namespace_validation_mode = mode
    end

    def entity_restoration_mode=(mode)
      mode = mode.to_sym
      unless ENTITY_RESTORATION_MODES.include?(mode)
        raise ArgumentError,
              "Invalid entity_restoration_mode: #{mode}. Must be one of: #{ENTITY_RESTORATION_MODES.join(', ')}"
      end

      @entity_restoration_mode = mode
    end

    # Backward compatibility: convert old boolean to new symbol
    def load_external_entities=(value)
      @entity_load_mode = case value
                          when true then :required
                          when false then :disabled
                          else value
                          end
    end

    def load_external_entities
      @entity_load_mode == :required
    end
  end
end
