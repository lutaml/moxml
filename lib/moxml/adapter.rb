# frozen_string_literal: true

module Moxml
  module Adapter
    autoload :Base, "moxml/adapter/base"
    autoload :CustomizedOga, "moxml/adapter/customized_oga"
    autoload :CustomizedOx, "moxml/adapter/customized_ox"
    autoload :CustomizedRexml, "moxml/adapter/customized_rexml"
    autoload :CustomizedLibxml, "moxml/adapter/customized_libxml"

    AVAILABLE_ADAPTERS = %i[nokogiri oga rexml ox headed_ox libxml].freeze

    # Adapters that work under the Opal (JavaScript) runtime.
    # Oga is pure Ruby and designed with Opal compatibility in mind — it is the
    # canonical XML parser for the JavaScript runtime. REXML is also pure Ruby
    # but requires extensive runtime compat shims (regex features like /n,
    # \u{...}, (?-mix:...) don't transpile cleanly), so it is opt-in only.
    OPAL_AVAILABLE_ADAPTERS = %i[oga rexml].freeze

    # Registry mapping adapter names to their class name suffixes.
    # Special cases (like :headed_ox → "HeadedOx") live here instead of
    # a case statement, keeping the dispatch open for extension.
    CONST_NAME_MAP = {
      headed_ox: "HeadedOx",
    }.freeze

    class << self
      def load(name)
        validate_platform!(name)
        require_adapter(name)
        const_name = const_name_for(name)
        const_get(const_name)
      rescue LoadError => e
        raise Moxml::AdapterError.new(
          "Could not load #{name} adapter. Please ensure the #{name} gem is installed",
          adapter: name,
          operation: "load",
          native_error: e,
        )
      end

      def available?(name)
        platform_adapters.include?(name.to_sym)
      end

      def platform_adapters
        RUBY_ENGINE == "opal" ? OPAL_AVAILABLE_ADAPTERS : AVAILABLE_ADAPTERS
      end

      private

      def validate_platform!(name)
        return if platform_adapters.include?(name.to_sym)

        available = platform_adapters.join(", ")
        raise Moxml::AdapterError.new(
          "The '#{name}' adapter is not available on this platform. Available: #{available}",
          adapter: name,
          operation: "platform_check",
        )
      end

      def const_name_for(name)
        CONST_NAME_MAP[name.to_sym] || name.to_s.capitalize
      end

      def require_adapter(name)
        # Opal pre-loads all dependencies via the Rakefile; skip runtime require.
        return if RUBY_ENGINE == "opal"

        require "moxml/adapter/base"
        require "moxml/adapter/#{name}"
      rescue LoadError
        begin
          require name.to_s
          require "moxml/adapter/#{name}"
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
