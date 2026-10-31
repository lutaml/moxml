# frozen_string_literal: true

module Moxml
  module Adapter
    # Extension contract (#494): adding an adapter is exactly the trio
    # below — nothing else, anywhere. The dispatch is open for
    # extension and closed against edit: registration is data, the
    # load path is generic, and spec/moxml/adapter_registry_spec.rb
    # walks the registry mechanically so a skipped leg fails there.
    #
    #   1. one entry in AVAILABLE_ADAPTERS,
    #   2. a requireable file at moxml/adapter/<name> (a
    #      `Customized<Name>` namespace module is optional),
    #   3. a subclass of Adapter::Base in that file.
    #
    # Deprecated adapters live in DEPRECATED_ADAPTERS (still fully
    # registered and loadable) until their removal milestone.
    autoload :Base, "moxml/adapter/base"
    autoload :CustomizedOga, "moxml/adapter/customized_oga"
    autoload :CustomizedOx, "moxml/adapter/customized_ox"
    autoload :CustomizedRexml, "moxml/adapter/customized_rexml"
    autoload :CustomizedLibxml, "moxml/adapter/customized_libxml"
    autoload :CustomizedLeptris, "moxml/adapter/customized_leptris"

    AVAILABLE_ADAPTERS = %i[nokogiri oga rexml ox headed_ox libxml leptris].freeze

    # Adapters that work under the Opal (JavaScript) runtime.
    # Oga is pure Ruby and designed with Opal compatibility in mind — it is the
    # canonical XML parser for the JavaScript runtime. REXML is also pure Ruby
    # but requires extensive runtime compat shims (regex features like /n,
    # \u{...}, (?-mix:...) don't transpile cleanly), so it is opt-in only.
    # Registry mapping adapter names to their class name suffixes.
    # Special cases (like :headed_ox → "HeadedOx") live here instead of
    # a case statement, keeping the dispatch open for extension.
    CONST_NAME_MAP = {
      headed_ox: "HeadedOx",
    }.freeze

    # Adapters in their deprecation cycle (#491): warned once per
    # process at configuration, removed after the cycle. The value is
    # the migration guidance shown in the warning.
    DEPRECATED_ADAPTERS = {
      headed_ox: "use :leptris (primary) or :nokogiri; headed_ox is a pure alias of :ox",
      libxml: "use :nokogiri — the same libxml2 engine, governed by the consistency suite",
      ox: "use :leptris (primary) or :nokogiri",
    }.freeze

    class << self
      # One-time deprecation notice per adapter per process (#491).
      def warn_deprecated!(name)
        guidance = DEPRECATED_ADAPTERS[name.to_sym]
        return unless guidance
        return if (@deprecation_warned ||= {})[name.to_sym]

        @deprecation_warned[name.to_sym] = true
        warn "moxml: the :#{name} adapter is deprecated and will be " \
             "removed; #{guidance}"
      end

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
        AVAILABLE_ADAPTERS
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
