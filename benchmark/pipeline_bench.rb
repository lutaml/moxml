# frozen_string_literal: true

# Consumer-pipeline benchmark leg (issue #198): measures a nested
# document walked into typed objects — the shape consumers actually
# run, where engine-level numbers hide wrapper overhead (Amdahl).
# Reports fresh-run medians with GC.stat allocation deltas.
require "moxml"
require "nokogiri"

ADAPTER = (ENV["PIPELINE_ADAPTER"] || "leptris").to_sym
REPS = (ENV["PIPELINE_REPS"] || 7).to_i

parts = [%(<?xml version="1.0"?><catalog>)]
150.times do |i|
  parts << %(<record id="r#{i}" kind="k#{i % 3}">)
  6.times { |j| parts << %(<field name="f#{j}" unit="u#{j}">value #{i}.#{j}</field>) }
  parts << %(</record>)
end
parts << %(</catalog>)
XML = parts.join

Field = Struct.new(:name, :unit, :value)
Record = Struct.new(:id, :kind, :fields)
Catalog = Struct.new(:records)

def walk_document(adapter_name)
  ctx = Moxml.new(adapter_name)
  doc = ctx.parse(XML)
  catalog = Catalog.new([])
  doc.root.children.each do |rec|
    next unless rec.is_a?(Moxml::Element)

    record = Record.new(rec["id"], rec["kind"], [])
    rec.children.each do |f|
      next unless f.is_a?(Moxml::Element)

      record.fields << Field.new(f["name"], f["unit"], f.text)
    end
    catalog.records << record
  end
  raise "shape" unless catalog.records.size == 150

  raise "content" unless catalog.records[7].fields[3].value.include?("7.3")

  catalog
end

def measure(adapter_name)
  walk_document(adapter_name) # warm: autoloads off the books
  times = []
  allocs = nil
  REPS.times do
    GC.start
    a0 = GC.stat(:total_allocated_objects)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    walk_document(adapter_name)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    a1 = GC.stat(:total_allocated_objects)
    times << ((t1 - t0) * 1e6)
    allocs = a1 - a0
  end
  median = times.sort[times.size / 2]
  [median, allocs]
end

noko_med, noko_alloc = measure(:nokogiri)
puts format("pipeline nokogiri: median %<med>7.0fµs  %<allocs>6d allocs", med: noko_med, allocs: noko_alloc)
target_med, target_alloc = measure(ADAPTER)
puts format("pipeline %<adapter>-8s: median %<med>7.0fµs  %<allocs>6d allocs  (%<ratio>.2fx, allocs %<aratio>.2fx)",
            adapter: ADAPTER, med: target_med, allocs: target_alloc,
            ratio: noko_med / target_med, aratio: noko_alloc.to_f / target_alloc)
puts format("(one-shot shape: parse + typed walk + content asserts; YJIT=%<yjit>s; load %<load>.1f)",
            yjit: ENV["RUBY_YJIT_ENABLE"] ? "on" : "off",
            load: `sysctl -n vm.loadavg`.split[1].to_f)
