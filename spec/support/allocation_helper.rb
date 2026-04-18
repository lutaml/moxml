# frozen_string_literal: true

require "set"

# Shared helper for allocation guard specs.
#
# Provides:
# - Precise allocation counting via GC.stat
# - Per-adapter threshold configuration
# - Adapter availability checks
# - Optional StackProf diagnostic on guard failure
module AllocationHelper
  # Adapters to guard in CI (ordered by importance).
  # Skip REXML/LibXML — not used in production.
  GUARDED_ADAPTERS = %i[nokogiri ox headed_ox oga].freeze

  # Per-adapter allocation thresholds.
  # Format: { operation => { adapter => max_allocations } }
  #
  # Thresholds calibrated at ~2x measured baseline (2026-04-18).
  # All lazy-parse adapters (nokogiri, ox, headed_ox) share similar profiles.
  # OGA is pure Ruby so naturally allocates more.
  THRESHOLDS = {
    # Parse a 100-element document (no subsequent access).
    # Measured: nokogiri=299, ox=1003, headed_ox=1001, oga=8732
    parse_100: {
      nokogiri: 600,
      ox: 2500,
      headed_ox: 2500,
      oga: 18_000,
    },
    # Parse a 50-element document.
    # Measured: nokogiri=148, ox=501, headed_ox=501, oga=4365
    parse_50: {
      nokogiri: 300,
      ox: 1200,
      headed_ox: 1200,
      oga: 9000,
    },
    # Access root.name after parse (lazy wrapping overhead).
    # Measured: nokogiri=317, ox=1013, headed_ox=1009, oga=8673
    parse_and_root: {
      nokogiri: 700,
      ox: 2500,
      headed_ox: 2500,
      oga: 18_000,
    },
    # First access to children (NodeSet construction).
    first_children_access: {
      nokogiri: 200,
      ox: 200,
      headed_ox: 200,
      oga: 300,
    },
    # Second access to children (should be ~0 — cached).
    # Measured: all adapters = 1-3
    cached_children_access: {
      nokogiri: 5,
      ox: 5,
      headed_ox: 5,
      oga: 5,
    },
    # Second access to attributes (should be ~0 — cached).
    # Measured: all adapters = 1
    cached_attributes_access: {
      nokogiri: 5,
      ox: 5,
      headed_ox: 5,
      oga: 5,
    },
    # Second iteration of NodeSet (wrap cache hit).
    # Measured: all adapters = 2
    cached_iteration: {
      nokogiri: 10,
      ox: 10,
      headed_ox: 10,
      oga: 10,
    },
    # Parse + serialize round-trip (50 elements).
    # Measured: nokogiri=222, ox=893, headed_ox=882, oga=9523
    round_trip: {
      nokogiri: 500,
      ox: 2000,
      headed_ox: 2000,
      oga: 20_000,
    },
    # Ratio of allocations for 200-element vs 100-element parse.
    # Must be <= max (linear growth). Quadratic would be > 4x.
    # Measured: nokogiri=2.01, ox=2.0, headed_ox=2.0, oga=1.99
    scalability_ratio: {
      nokogiri: 2.5,
      ox: 2.5,
      headed_ox: 2.5,
      oga: 2.5,
    },
  }.freeze

  class << self
    # Count object allocations during a block.
    # Uses GC.stat[:total_allocated_objects] for precision.
    def count_allocations
      GC.start
      GC.disable
      before = GC.stat[:total_allocated_objects] || ObjectSpace.count_objects[:TOTAL]
      result = yield
      after = GC.stat[:total_allocated_objects] || ObjectSpace.count_objects[:TOTAL]
      after - before
    ensure
      GC.enable
      result
    end

    # Check if an adapter is available for testing.
    def adapter_available?(adapter_name)
      ctx = Moxml::Context.new(adapter_name)
      ctx.parse("<root/>")
      true
    rescue StandardError
      false
    end

    # Get the allocation threshold for an adapter + operation.
    def threshold(adapter_name, operation)
      THRESHOLDS.dig(operation, adapter_name) ||
        raise(ArgumentError, "No threshold for #{adapter_name}/#{operation}")
    end

    # Run StackProf and return top hotspots as a diagnostic string.
    # Tries :obj mode first (allocation profiling), falls back to :wall.
    def profile_allocations(&block)
      require "stackprof"

      # :obj mode tracks object allocations but requires platform support.
      # :wall mode tracks wall-clock time — less precise but always available.
      result = begin
        StackProf.run(mode: :obj, &block)
      rescue ArgumentError
        StackProf.run(mode: :wall, &block)
      end
      return nil unless result

      frames = result[:frames]
      total_samples = result[:samples]

      hotspots = frames.sort_by { |_, f| -f[:samples] }.first(10)
      lines = ["StackProf hotspot (#{total_samples} total samples):"]
      hotspots.each do |name, frame|
        pct = (frame[:samples].to_f / total_samples * 100).round(1)
        lines << "  #{pct}% #{name} (#{frame[:samples]} samples)"
      end
      lines.join("\n")
    rescue LoadError
      "StackProf not available — add gem 'stackprof' to Gemfile"
    end
  end
end

# Generate a test XML document with N elements.
# Each element has 2 attributes and nested text content.
def generate_xml(element_count)
  inner = element_count.times.map do |i|
    "<elem#{i % 10} id=\"#{i}\" type=\"t#{i % 3}\">text#{i}</elem#{i % 10}>"
  end.join
  "<root>#{inner}</root>"
end
