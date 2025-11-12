# frozen_string_literal: true

require_relative "adapter/base"

module Moxml
  module Adapter
    AVALIABLE_ADAPTERS = %i[nokogiri oga rexml ox libxml].freeze

    class << self
      def load(name)
        require_adapter(name)
        const_get(name.to_s.capitalize)
      rescue LoadError => e
        raise Moxml::AdapterError.new(
          "Could not load #{name} adapter. Please ensure the #{name} gem is installed",
          adapter: name,
          operation: "load",
          native_error: e,
        )
      end

      private

      def require_adapter(name)
        require "#{__dir__}/adapter/#{name}"
      rescue LoadError
        begin
          require name.to_s
          require "#{__dir__}/adapter/#{name}"
        rescue LoadError => e
          raise Moxml::AdapterError.new(
            "Failed to load #{name} adapter",
            adapter: name,
            operation: "require",
            native_error: e,
          )
        end
      end
    end
  end
end
