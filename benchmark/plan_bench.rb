# frozen_string_literal: true

# Plan-bench regression lock (leptris follow-up to #249): the plan
# path must stay at or near raw-nokogiri CPU parity on the consumer
# shape. Run via `rake benchmark:plan` or with LEPTRIS_BENCH_LOCK=1
# to enforce the ceiling (CI): plan <= nokogiri * 1.5 — failures
# mean an adapter or plan change regressed the compiled walk.
require "moxml"
require "nokogiri"

Field = Struct.new(:name, :unit, :value)
Record = Struct.new(:id, :kind, :fields)
Catalog = Struct.new(:records)

parts = [%(<?xml version="1.0"?><catalog>)]
150.times do |i|
  parts << %(<record id="r#{i}" kind="k#{i % 3}">)
  6.times { |j| parts << %(<field name="f#{j}" unit="u#{j}">value #{i}.#{j}</field>) }
  parts << %(</record>)
end
parts << %(</catalog>)
XML = parts.join

CTX = Moxml.new(:leptris)

STRUCT_PLAN = Moxml::StructPlan.new do
  element "record", Record, attrs: { "id" => :id, "kind" => :kind }, children: :fields
  element "field", Field, attrs: { "name" => :name, "unit" => :unit }, text: :value
end

PLAN = Moxml::Plan.new do
  on("record") { |attrs, _t, fields| Record.new(attrs["id"], attrs["kind"], fields) }
  on("field")  { |attrs, text, _k| Field.new(attrs["name"], attrs["unit"], text) }
end

def plan_run
  records = PLAN.parse(XML, CTX)
  raise "shape" unless records.size == 150 && records[7].fields[3].value == "value 7.3"

  records
end

def struct_run
  records = STRUCT_PLAN.parse(XML, CTX)
  raise "shape" unless records.size == 150 && records[7].fields[3].value == "value 7.3"

  records
end

def wrapper_run
  doc = CTX.parse(XML)
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

  catalog
end

def nokogiri_run
  doc = Nokogiri::XML(XML)
  catalog = Catalog.new([])
  doc.root.children.each do |rec|
    next unless rec.is_a?(Nokogiri::XML::Element)

    record = Record.new(rec["id"], rec["kind"], [])
    rec.children.each do |f|
      next unless f.is_a?(Nokogiri::XML::Element)

      record.fields << Field.new(f["name"], f["unit"], f.text)
    end
    catalog.records << record
  end
  raise "shape" unless catalog.records.size == 150

  catalog
end

REPS = 200

def bench(&block)
  times = []
  allocs = []
  REPS.times do
    GC.start
    a0 = GC.stat(:total_allocated_objects)
    t0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    yield
    times << (Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - t0)
    allocs << (GC.stat(:total_allocated_objects) - a0)
  end
  [times.sort[times.size / 2] * 1e6, allocs.min]
end

# The parity lock needs the lean plan rows (binding 1.9.194.2+);
# on older bindings the plan runs the generic fallback and the
# ceiling is meaningless — report and exit clean.
if Gem::Version.new(Leptris::VERSION) < Gem::Version.new("1.9.194.2")
  puts "SKIP parity lock: leptris #{Leptris::VERSION} lacks snapshot_rows (needs 1.9.194.2)"
  exit 0
end

# warm
plan_run
struct_run
wrapper_run
nokogiri_run

struct_us = nil
struct_allocs = nil
if Gem::Version.new(Leptris::VERSION) >= Gem::Version.new("1.9.197.1")
  struct_us, struct_allocs = bench { struct_run }
end
plan_us,  plan_allocs  = bench { plan_run }
wrap_us,  wrap_allocs  = bench { wrapper_run }
nk_us,    nk_allocs    = bench { nokogiri_run }

if struct_us
  puts format("struct   (parse+materialize) %<t>8.0f us  %<a>7d allocs",
              t: struct_us, a: struct_allocs)
end
puts format("plan     (parse+materialize) %<t>8.0f us  %<a>7d allocs",
            t: plan_us, a: plan_allocs)
puts format("wrapper  (parse+walk)       %<t>8.0f us  %<a>7d allocs",
            t: wrap_us, a: wrap_allocs)
puts format("nokogiri (parse+walk)       %<t>8.0f us  %<a>7d allocs",
            t: nk_us, a: nk_allocs)
puts format("plan/nokogiri %<r>.2fx (ceiling 1.50x for the CI lock)",
            r: plan_us / nk_us)

exit(1) if ENV["LEPTRIS_BENCH_LOCK"] && plan_us > nk_us * 1.5
