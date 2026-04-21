# frozen_string_literal: true

require "json"
require "set"

module Moxml
  # EntityRegistry maintains a knowledge base of XML entity definitions.
  #
  # Data source: W3C XML Core WG Character Entities (bundled)
  # https://www.w3.org/2003/entities/2007/htmlmathml
  #
  # The W3C entity data is bundled in data/w3c_entities.json and loaded
  # from the gem's data directory. For development, MOXML_ENTITY_DEFINITIONS_PATH
  # can be set to an external copy.
  #
  # Per W3C XML Core WG guidance:
  # - Character entities are XML internal general entities providing a name for a single Unicode character
  # - Standard XML entities (amp, lt, gt, quot, apos) are implicitly declared per XML specification
  # - External entity sets (like HTML, MathML) can be referenced via DTD parameter entities
  #
  # @example Basic usage
  #   registry = EntityRegistry.new
  #   registry.declared?("amp")  # => true
  #   registry.codepoint_for_name("amp")  # => 38
  #
  class EntityRegistry
    # W3C entity data file name
    ENTITY_DATA_FILE = "w3c_entities.json"

    # Standard XML predefined entities (XML spec §4.6)
    STANDARD_CODEPOINTS = Set[0x26, 0x3C, 0x3E, 0x22, 0x27].freeze

    class << self
      # Get the raw entity data from the bundled JSON source
      # @return [Hash{String => String}] entity name to character mapping
      def entity_data
        @entity_data ||= load_entity_data
      end

      # Get the default registry instance (lazy loaded)
      # @return [EntityRegistry]
      def default
        @default ||= new
      end

      # Reset the default registry (mainly for testing)
      # @return [void]
      def reset
        @default = nil
        @entity_data = nil
      end

      private

      # Load entity data from bundled gem data or local file
      # @return [Hash{String => String}]
      def load_entity_data
        # Try multiple paths in order of priority
        paths_to_try = []

        # 1. Environment variable override (for development/custom setups)
        if ENV["MOXML_ENTITY_DEFINITIONS_PATH"]
          paths_to_try << ENV["MOXML_ENTITY_DEFINITIONS_PATH"]
        end

        # 2. Relative to moxml lib directory (for development/installation)
        # __dir__ is lib/moxml/entity_registry.rb
        # So ../../data/ goes to project_root/data/
        paths_to_try << File.expand_path(
          "../../data/#{ENTITY_DATA_FILE}",
          __dir__,
        )

        # 3. External xml-entities sibling directory (common development setup)
        paths_to_try << File.expand_path(
          "../../external/xml-entities/docs/2007/htmlmathml.json",
          __dir__,
        )

        data = nil
        paths_to_try.uniq.each do |path|
          next unless path && File.exist?(path)

          begin
            data = File.read(path)
            break
          rescue StandardError
            # Try next path
          end
        end

        unless data
          raise EntityDataError,
                "Entity data not found. Set MOXML_ENTITY_DEFINITIONS_PATH or ensure data/#{ENTITY_DATA_FILE} exists."
        end

        JSON.parse(data)["characters"]
      rescue StandardError => e
        raise EntityDataError, "Failed to load entity definitions: #{e.message}"
      end
    end

    # Error raised when entity data cannot be loaded
    class EntityDataError < StandardError; end

    # @return [Hash{String => Integer}] entity name to codepoint mapping
    attr_reader :by_name

    # @return [Hash{Integer => Array<String>}] codepoint to entity names mapping
    attr_reader :by_codepoint

    # @param mode [Symbol] Loading mode: :required, :optional, :disabled, :custom
    # @param entity_provider [Proc, nil] Custom entity provider proc/lambda
    def initialize(mode: :required, entity_provider: nil)
      @by_name = {}
      @by_codepoint = Hash.new { |h, k| h[k] = [] }
      @mode = mode
      @entity_provider = entity_provider

      case mode
      when :required
        load_from_entity_data
      when :optional
        load_from_entity_data_optional
      when :custom
        load_custom_entities
      when :disabled
        # Don't load anything - empty registry
      end
    end

    # Check if an entity name is declared
    # @param name [String] entity name (e.g., "amp", "nbsp")
    # @return [Boolean]
    def declared?(name)
      @by_name.key?(name)
    end

    # Get the Unicode codepoint for an entity name
    # @param name [String] entity name
    # @return [Integer, nil] codepoint or nil if not found
    def codepoint_for_name(name)
      @by_name[name]
    end

    # Get all entity names for a codepoint
    # @param codepoint [Integer] Unicode codepoint
    # @return [Array<String>] entity names mapping to this codepoint
    def names_for_codepoint(codepoint)
      @by_codepoint[codepoint]
    end

    # Get the primary (preferred) entity name for a codepoint
    # @param codepoint [Integer] Unicode codepoint
    # @return [String, nil] primary entity name or nil
    def primary_name_for_codepoint(codepoint)
      @by_codepoint[codepoint]&.first
    end

    # Check if a codepoint is one of the 5 standard XML predefined entities
    # @param codepoint [Integer] Unicode codepoint
    # @return [Boolean]
    def standard_entity?(codepoint)
      STANDARD_CODEPOINTS.include?(codepoint)
    end

    # Determine if an entity reference should be restored for a codepoint.
    # Standard XML entities are always restored (required by XML spec).
    # Non-standard entities are only restored when restore_entities is enabled.
    # @param codepoint [Integer] Unicode codepoint
    # @param config [Moxml::Config] configuration object
    # @return [Boolean]
    def should_restore?(codepoint, config:)
      name = primary_name_for_codepoint(codepoint)
      return false unless name
      return true if standard_entity?(codepoint)
      config.restore_entities
    end

    # Returns the set of codepoints that could potentially be restored as entities.
    # Used by DocumentBuilder for O(1) fast-path checks.
    # @return [Set<Integer>]
    def restorable_codepoints
      @restorable_codepoints ||= if @by_name.empty?
                                    STANDARD_CODEPOINTS
                                  else
                                    Set.new(@by_name.values).freeze
                                  end
    end

    # Register additional entities
    # @param entities [Hash{String => Integer}] name => codepoint mapping
    # @return [self]
    def register(entities)
      entities.each do |name, codepoint|
        @by_name[name] = codepoint
        @by_codepoint[codepoint] ||= []
        @by_codepoint[codepoint] << name unless @by_codepoint[codepoint].include?(name)
      end
      self
    end

    # Load all entities from the W3C HTMLMathML entity set
    # This is called automatically by initialize
    # @return [self]
    def load_html5
      # All entities are loaded by default from initialize
      self
    end

    # Load MathML entity set (included in HTMLMathML)
    # @return [self]
    def load_mathml
      # All entities are loaded by default from initialize
      self
    end

    # Load ISO entity sets (included in HTMLMathML)
    # @param _set_name [Symbol] (ignored, all loaded together)
    # @return [self]
    def load_iso(_set_name = :iso8879)
      # All entities are loaded by default from initialize
      self
    end

    # Load all standard entity sets
    # @return [self]
    def load_all
      # All entities are loaded by default from initialize
      self
    end

    # Clear all entities (reset to empty)
    # @return [self]
    def clear!
      @by_name = {}
      @by_codepoint = Hash.new { |h, k| h[k] = [] }
      self
    end

    private

    # Load entities from the centralized JSON data source
    # @raise [EntityDataError] if entity data is required but cannot be loaded
    # @return [void]
    def load_from_entity_data
      data = self.class.entity_data

      if data.nil?
        raise EntityDataError,
              "Entity data is not available. Set entity_load_mode to :optional or :disabled to skip entity loading."
      end

      data.each do |name, char|
        codepoint = parse_codepoint(char)
        next unless codepoint

        @by_name[name] = codepoint
        @by_codepoint[codepoint] ||= []
        @by_codepoint[codepoint] << name unless @by_codepoint[codepoint].include?(name)
      end
    end

    # Load entities from the centralized JSON data source (optional mode)
    # Silently continues if entity data cannot be loaded
    # @return [void]
    def load_from_entity_data_optional
      data = self.class.entity_data
      return unless data

      data.each do |name, char|
        codepoint = parse_codepoint(char)
        next unless codepoint

        @by_name[name] = codepoint
        @by_codepoint[codepoint] ||= []
        @by_codepoint[codepoint] << name unless @by_codepoint[codepoint].include?(name)
      end
    rescue EntityDataError
      # Silently ignore - optional mode
    end

    # Load custom entities from the provided entity provider
    # @return [void]
    def load_custom_entities
      return unless @entity_provider

      entities = @entity_provider.call
      return unless entities

      entities.each do |name, codepoint|
        @by_name[name] = codepoint
        @by_codepoint[codepoint] ||= []
        @by_codepoint[codepoint] << name unless @by_codepoint[codepoint].include?(name)
      end
    end

    # Parse a Unicode character escape to codepoint
    # @param char [String] character or escape sequence
    # @return [Integer, nil]
    def parse_codepoint(char)
      if char.start_with?("\\u")
        # Handle \uXXXX format
        char.unicode_normalize(:nfc)[2..].to_i(16)
      else
        # Single character - get its ord
        char.ord
      end
    rescue StandardError
      nil
    end
  end
end
