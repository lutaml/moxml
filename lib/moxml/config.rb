# frozen_string_literal: true

module Moxml
  class Config
    LINE_ENDING_LF = "\n"
    LINE_ENDING_CRLF = "\r\n"
    VALID_LINE_ENDINGS = [LINE_ENDING_LF, LINE_ENDING_CRLF].freeze
    VALID_ADAPTERS = %i[nokogiri oga rexml ox headed_ox libxml leptris].freeze
    # Preferred CRuby default (issue #96): fastest on every measured
    # operation and the cleanest deployment story. Only takes effect
    # when the installed leptris supports programmatic document
    # construction (Leptris::XML::Document.create); otherwise moxml
    # falls back to FALLBACK_ADAPTER so released-gem environments keep
    # working.
    PREFERRED_ADAPTER = :leptris
    FALLBACK_ADAPTER = :nokogiri

    # Entity loading modes:
    # - :required - Must load entities, raise error if unavailable (default)
    # - :optional - Try to load, continue silently if unavailable
    # - :disabled - Don't load entities, use empty registry
    # - :custom - Use custom entity provider via entity_provider callback
    # Entity-reference preservation mode (leptris-ruby#212 / upstream
    # #1094): :expand (default) keeps the shipped behavior (entities
    # expanded at parse, marker-driven round-trip); :keep enables
    # first-class EntityReference nodes and skips the marker machinery
    # when the binding supports it (leptris >= 1.9.177).
    ENTITY_MODES = %i[expand keep].freeze

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
        preferred = leptris_preferred_available?
        return PREFERRED_ADAPTER if preferred == true

        # Issue #384: a PRESENT-but-unusable leptris (broken native
        # bundle, adapter load failure) must not degrade silently —
        # validation semantics differ per adapter, so the
        # substitution is announced. A machine without the gem at
        # all is a normal nokogiri/rexml deployment: no noise.
        if preferred == :broken
          Kernel.warn(
            "moxml: the leptris adapter is installed but unusable " \
            "(see the preceding error); falling back to " \
            "#{detect_loaded_adapter || FALLBACK_ADAPTER} — " \
            "adapter-specific behavior (XSD validation, " \
            "serialization) will differ",
          )
        end

        detect_loaded_adapter || FALLBACK_ADAPTER
      end

      # True when the leptris gem is installed AND meets the adapter's
      # binding floor (issue #149; 1.9.32 — traverse bounding #89,
      # built-docs parts #91, and every capability surface the adapter
      # now assumes). Memoized: the probe runs once. Below the floor
      # the default falls back to Nokogiri rather than driving a
      # binding the adapter no longer accommodates.
      def leptris_preferred_available?
        return @leptris_preferred_available if defined?(@leptris_preferred_available)

        @leptris_preferred_available =
          begin
            require "leptris"
            Moxml::Adapter.load(:leptris)
            Gem::Version.new(::Leptris::VERSION) >=
              Gem::Version.new(Moxml::Adapter::Leptris::MINIMUM_BINDING_VERSION)
          rescue LoadError
            # Not installed: a normal deployment shape, silent.
            false
          rescue NameError, Moxml::AdapterError
            # Installed but unusable (adapter load failure): loud.
            :broken
          end
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

    # Ox whitespace policy (issue #189): ::Ox.parse hardcodes
    # skip: :skip_white, which collapses whitespace runs inside text
    # content — xml:space="preserve" documents round-trip mangled.
    # The adapter parses with ::Ox.load instead; these defaults keep
    # every character of text content (inter-element indentation is
    # dropped by Ox's generic mode under every skip setting, so the
    # child lists stay identical to the old parse).
    OX_DEFAULT_SKIP = :skip_none
    OX_DEFAULT_MODE = :generic
    OX_VALID_SKIPS = %i[skip_none skip_white skip_off].freeze
    OX_VALID_MODES = %i[generic hash object].freeze

    attr_reader :adapter_name, :default_line_ending
    attr_accessor :strict_parsing,
                  :builder_strict,
                  :default_encoding,
                  :default_indent,
                  :restore_entities,
                  :preload_entity_sets,
                  :entity_load_mode,
                  :entity_provider,
                  :namespace_validation_mode,
                  :entity_restoration_mode,
                  :entity_mode,
                  :ox_skip,
                  :ox_mode

    def ox_skip=(value)
      unless OX_VALID_SKIPS.include?(value)
        raise ArgumentError,
              "Invalid ox_skip: #{value.inspect}. Must be one of #{OX_VALID_SKIPS.inspect}"
      end

      @ox_skip = value
    end

    def ox_mode=(value)
      unless OX_VALID_MODES.include?(value)
        raise ArgumentError,
              "Invalid ox_mode: #{value.inspect}. Must be one of #{OX_VALID_MODES.inspect}"
      end

      @ox_mode = value
    end

    def default_line_ending=(value)
      unless VALID_LINE_ENDINGS.include?(value)
        raise ArgumentError,
              "Invalid line_ending: #{value.inspect}. " \
              "Must be Config::LINE_ENDING_LF or Config::LINE_ENDING_CRLF"
      end

      @default_line_ending = value
    end

    def initialize(adapter_name = nil, strict_parsing = nil,
                   default_encoding = nil)
      self.adapter = adapter_name || Config.default.adapter_name
      @strict_parsing = strict_parsing || Config.default.strict_parsing
      # Constant-initialized (not Config.default fallback): the
      # default Config constructs via Config.default — a fallback
      # read there recurses. Global-default propagation for these
      # knobs is not part of the contract; per-context is (#189).
      @ox_skip = OX_DEFAULT_SKIP
      @ox_mode = OX_DEFAULT_MODE
      @default_encoding = default_encoding || Config.default.default_encoding
      @default_indent = 2
      @default_line_ending = LINE_ENDING_LF
      @restore_entities = false
      @preload_entity_sets = []
      @entity_load_mode = :required
      @entity_provider = nil
      @namespace_validation_mode = :strict
      @entity_restoration_mode = :lenient
      # #371: Builder method_missing creates elements for unknown
      # methods (the DSL contract). builder_strict flips that to
      # raising NoMethodError — external helper calls stop
      # silently becoming empty elements.
      @builder_strict = false
      @entity_mode = :expand
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
      mode = mode.to_sym
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

    def entity_mode=(mode)
      mode = mode.to_sym
      unless ENTITY_MODES.include?(mode)
        raise ArgumentError,
              "Invalid entity_mode: #{mode.inspect}. Must be one of: #{ENTITY_MODES.join(', ')}"
      end

      @entity_mode = mode
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
