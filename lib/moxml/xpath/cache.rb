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
        # One insertion-ordered hash: re-inserting a key on access
        # makes the first entry the least-recently-used. An
        # Array-backed order list cost ~600ns per hit in O(n)
        # deletes — the adapter's xpath path hits three caches per
        # call.
        @entries = {}
      end

      # Gets a value from the cache or sets it using the provided block.
      #
      # @param [Object] key Cache key
      # @yield Block to execute if key is not in cache
      # @return [Object] Cached or newly computed value
      def get_or_set(key)
        if @entries.key?(key)
          value = @entries.delete(key)
          @entries[key] = value
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
        @entries.delete(key)
        @entries[key] = value
        @entries.shift if @entries.size > @max_size
        value
      end

      # Gets a value from the cache.
      #
      # @param [Object] key
      # @return [Object, nil]
      def get(key)
        return unless @entries.key?(key)

        value = @entries.delete(key)
        @entries[key] = value
      end

      # Clears the cache.
      #
      # @return [void]
      def clear
        @entries.clear
      end

      # Returns the current size of the cache.
      #
      # @return [Integer]
      def size
        @entries.size
      end

      # Checks if a key exists in the cache.
      #
      # @param [Object] key
      # @return [Boolean]
      def key?(key)
        @entries.key?(key)
      end
    end
  end
end
