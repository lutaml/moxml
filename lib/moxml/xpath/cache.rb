# frozen_string_literal: true

module Moxml
  module XPath
    # Simple LRU (Least Recently Used) cache for compiled XPath expressions.
    #
    # @private
    class Cache
      DEFAULT_SIZE = 1000

      # @param [Integer] max_size Maximum number of entries to cache
      def initialize(max_size = DEFAULT_SIZE)
        @max_size = max_size
        @cache = {}
        @access_order = []
      end

      # Gets a value from the cache or sets it using the provided block.
      #
      # @param [Object] key Cache key
      # @yield Block to execute if key is not in cache
      # @return [Object] Cached or newly computed value
      def get_or_set(key)
        if @cache.key?(key)
          # Move to end (most recently used)
          @access_order.delete(key)
          @access_order.push(key)
          @cache[key]
        else
          value = yield
          set(key, value)
          value
        end
      end

      # Sets a value in the cache.
      #
      # @param [Object] key
      # @param [Object] value
      # @return [Object] The value
      def set(key, value)
        if @cache.key?(key)
          @access_order.delete(key)
        elsif @cache.size >= @max_size
          # Remove least recently used
          lru_key = @access_order.shift
          @cache.delete(lru_key)
        end

        @cache[key] = value
        @access_order.push(key)
        value
      end

      # Gets a value from the cache.
      #
      # @param [Object] key
      # @return [Object, nil]
      def get(key)
        return unless @cache.key?(key)

        @access_order.delete(key)
        @access_order.push(key)
        @cache[key]
      end

      # Clears the cache.
      #
      # @return [void]
      def clear
        @cache.clear
        @access_order.clear
      end

      # Returns the current size of the cache.
      #
      # @return [Integer]
      def size
        @cache.size
      end

      # Checks if a key exists in the cache.
      #
      # @param [Object] key
      # @return [Boolean]
      def key?(key)
        @cache.key?(key)
      end
    end
  end
end
