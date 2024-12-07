# lib/moxml/config.rb
module Moxml
  class Config
    VALID_ADAPTERS = [:nokogiri, :oga, :ox].freeze
    DEFAULT_ADAPTER = VALID_ADAPTERS.first

    class << self
      def default
        @default ||= new(DEFAULT_ADAPTER, true, "UTF-8")
      end
    end

    attr_reader :adapter_name
    attr_accessor :strict_parsing,
                  :default_encoding,
                  :entity_encoding,
                  :default_indent

    def initialize(adapter_name = nil, strict_parsing = nil, default_encoding = nil)
      self.adapter = adapter_name || Config.default.adapter_name
      @strict_parsing = strict_parsing || Config.default.strict_parsing
      @default_encoding = default_encoding || Config.default.default_encoding
      # reserved for future use
      @default_indent = 2
      @entity_encoding = :basic
    end

    def adapter=(name)
      name = name.to_sym
      @adapter = nil

      unless VALID_ADAPTERS.include?(name)
        raise ArgumentError, "Invalid adapter: #{name}. Valid adapters are: #{VALID_ADAPTERS.join(", ")}"
      end

      @adapter_name = name
      adapter
    end

    alias default_adapter= adapter=

    def adapter
      @adapter ||= Adapter.load(@adapter_name)
    end
  end
end
