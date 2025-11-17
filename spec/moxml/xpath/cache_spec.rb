# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Cache do
  let(:cache) { described_class.new(3) } # Small cache for testing

  describe "#initialize" do
    it "creates a cache with default size" do
      default_cache = described_class.new
      expect(default_cache.size).to eq(0)
    end

    it "creates a cache with specified size" do
      custom_cache = described_class.new(10)
      expect(custom_cache.size).to eq(0)
    end
  end

  describe "#get_or_set" do
    it "calls block and caches result on cache miss" do
      call_count = 0

      result1 = cache.get_or_set("key1") do
        call_count += 1
        "value1"
      end

      expect(result1).to eq("value1")
      expect(call_count).to eq(1)
      expect(cache.size).to eq(1)
    end

    it "returns cached value on cache hit without calling block" do
      call_count = 0

      cache.get_or_set("key1") { "value1" }

      result = cache.get_or_set("key1") do
        call_count += 1
        "should not be called"
      end

      expect(result).to eq("value1")
      expect(call_count).to eq(0)
    end

    it "updates access order on cache hit" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      # Access key1 to make it most recently used
      cache.get_or_set("key1") { "unused" }

      # Add key4, which should evict key2 (least recently used)
      cache.set("key4", "value4")

      expect(cache.key?("key1")).to be(true)
      expect(cache.key?("key2")).to be(false)
      expect(cache.key?("key3")).to be(true)
      expect(cache.key?("key4")).to be(true)
    end
  end

  describe "#set" do
    it "adds a new key-value pair to the cache" do
      cache.set("key1", "value1")

      expect(cache.size).to eq(1)
      expect(cache.get("key1")).to eq("value1")
    end

    it "updates existing key and moves it to end" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      # Update key1
      cache.set("key1", "new_value1")

      # Add key4, should evict key2 (now least recently used)
      cache.set("key4", "value4")

      expect(cache.get("key1")).to eq("new_value1")
      expect(cache.key?("key2")).to be(false)
      expect(cache.key?("key3")).to be(true)
      expect(cache.key?("key4")).to be(true)
    end

    it "evicts least recently used entry when cache is full" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      expect(cache.size).to eq(3)

      # Add key4, should evict key1 (least recently used)
      cache.set("key4", "value4")

      expect(cache.size).to eq(3)
      expect(cache.key?("key1")).to be(false)
      expect(cache.key?("key4")).to be(true)
    end

    it "returns the set value" do
      result = cache.set("key1", "value1")
      expect(result).to eq("value1")
    end
  end

  describe "#get" do
    it "returns value for existing key" do
      cache.set("key1", "value1")

      expect(cache.get("key1")).to eq("value1")
    end

    it "returns nil for non-existent key" do
      expect(cache.get("nonexistent")).to be_nil
    end

    it "updates access order on get" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      # Access key1 to make it most recently used
      cache.get("key1")

      # Add key4, should evict key2 (now least recently used)
      cache.set("key4", "value4")

      expect(cache.key?("key1")).to be(true)
      expect(cache.key?("key2")).to be(false)
    end
  end

  describe "#clear" do
    it "removes all entries from the cache" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      expect(cache.size).to eq(3)

      cache.clear

      expect(cache.size).to eq(0)
      expect(cache.key?("key1")).to be(false)
      expect(cache.key?("key2")).to be(false)
      expect(cache.key?("key3")).to be(false)
    end

    it "works on empty cache" do
      empty_cache = described_class.new
      expect { empty_cache.clear }.not_to raise_error
      expect(empty_cache.size).to eq(0)
    end
  end

  describe "#size" do
    it "returns 0 for empty cache" do
      expect(cache.size).to eq(0)
    end

    it "returns correct size as items are added" do
      expect(cache.size).to eq(0)

      cache.set("key1", "value1")
      expect(cache.size).to eq(1)

      cache.set("key2", "value2")
      expect(cache.size).to eq(2)

      cache.set("key3", "value3")
      expect(cache.size).to eq(3)
    end

    it "does not exceed maximum size" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")
      cache.set("key4", "value4")

      expect(cache.size).to eq(3)
    end
  end

  describe "#key?" do
    it "returns true for existing keys" do
      cache.set("key1", "value1")

      expect(cache.key?("key1")).to be(true)
    end

    it "returns false for non-existent keys" do
      expect(cache.key?("nonexistent")).to be(false)
    end

    it "returns false after key is evicted" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")
      cache.set("key4", "value4") # Evicts key1

      expect(cache.key?("key1")).to be(false)
    end
  end

  describe "LRU eviction behavior" do
    it "evicts least recently set item" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      # key1 is least recently set
      cache.set("key4", "value4")

      expect(cache.key?("key1")).to be(false)
      expect(cache.key?("key2")).to be(true)
      expect(cache.key?("key3")).to be(true)
      expect(cache.key?("key4")).to be(true)
    end

    it "evicts least recently accessed item" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.set("key3", "value3")

      # Access key1 and key2, making key3 least recently used
      cache.get("key1")
      cache.get("key2")

      cache.set("key4", "value4")

      expect(cache.key?("key1")).to be(true)
      expect(cache.key?("key2")).to be(true)
      expect(cache.key?("key3")).to be(false)
      expect(cache.key?("key4")).to be(true)
    end

    it "handles interleaved sets and gets" do
      cache.set("key1", "value1")
      cache.set("key2", "value2")
      cache.get("key1") # key1 becomes most recent
      cache.set("key3", "value3")

      # key2 is least recently used
      cache.set("key4", "value4")

      expect(cache.key?("key1")).to be(true)
      expect(cache.key?("key2")).to be(false)
      expect(cache.key?("key3")).to be(true)
      expect(cache.key?("key4")).to be(true)
    end

    it "handles get_or_set in LRU order" do
      cache.get_or_set("key1") { "value1" }
      cache.get_or_set("key2") { "value2" }
      cache.get_or_set("key3") { "value3" }

      # Access key1 to make it recent
      cache.get_or_set("key1") { "unused" }

      # key2 is now least recent
      cache.get_or_set("key4") { "value4" }

      expect(cache.key?("key1")).to be(true)
      expect(cache.key?("key2")).to be(false)
      expect(cache.key?("key3")).to be(true)
      expect(cache.key?("key4")).to be(true)
    end
  end

  describe "edge cases" do
    it "handles cache with size 1" do
      tiny_cache = described_class.new(1)

      tiny_cache.set("key1", "value1")
      expect(tiny_cache.size).to eq(1)

      tiny_cache.set("key2", "value2")
      expect(tiny_cache.size).to eq(1)
      expect(tiny_cache.key?("key1")).to be(false)
      expect(tiny_cache.key?("key2")).to be(true)
    end

    it "handles nil values" do
      cache.set("key1", nil)

      expect(cache.key?("key1")).to be(true)
      expect(cache.get("key1")).to be_nil
    end

    it "handles various key types" do
      cache.set("string_key", "value1")
      cache.set(:symbol_key, "value2")
      cache.set(123, "value3")

      expect(cache.get("string_key")).to eq("value1")
      expect(cache.get(:symbol_key)).to eq("value2")
      expect(cache.get(123)).to eq("value3")
    end

    it "handles various value types" do
      cache.set("key1", "string")
      cache.set("key2", 42)
      cache.set("key3", [1, 2, 3])

      expect(cache.get("key1")).to eq("string")
      expect(cache.get("key2")).to eq(42)
      expect(cache.get("key3")).to eq([1, 2, 3])
    end

    it "handles updating same key multiple times" do
      cache.set("key1", "value1")
      cache.set("key1", "value2")
      cache.set("key1", "value3")

      expect(cache.size).to eq(1)
      expect(cache.get("key1")).to eq("value3")
    end

    it "handles large cache size" do
      large_cache = described_class.new(1000)

      500.times do |i|
        large_cache.set("key#{i}", "value#{i}")
      end

      expect(large_cache.size).to eq(500)
      expect(large_cache.get("key0")).to eq("value0")
      expect(large_cache.get("key499")).to eq("value499")
    end
  end

  describe "default size constant" do
    it "has DEFAULT_SIZE constant" do
      expect(described_class::DEFAULT_SIZE).to eq(1000)
    end

    it "uses DEFAULT_SIZE when no size specified" do
      default_cache = described_class.new

      # Fill with DEFAULT_SIZE + 1 items
      (described_class::DEFAULT_SIZE + 1).times do |i|
        default_cache.set("key#{i}", "value#{i}")
      end

      # Should have exactly DEFAULT_SIZE items
      expect(default_cache.size).to eq(described_class::DEFAULT_SIZE)

      # First item should be evicted
      expect(default_cache.key?("key0")).to be(false)
    end
  end
end
