# frozen_string_literal: true

# SAX bench row (leptris#1298 follow-up / moxml#279 item 4): the
# bulk record drain vs the callback Recorder on the canon parse-lane
# shape. Run via `rake benchmark:sax`; with LEPTRIS_BENCH_LOCK=1
# (CI) it exits 1 unless the drain stays materially cheaper than the
# recorder — records-walk allocations must land under half the
# recorder's, so the win stays visible and a regression re-opens
# the lane.
require "moxml"

item = "<item n=\"1\" kind=\"k\" id=\"i1\">value text</item>"
DOC = "<r>#{item * 225}<t>tail</t></r>".freeze # rubocop:disable Lint/ConstantDefinitionInBlock
DOCS = [DOC, DOC].freeze # rubocop:disable Lint/ConstantDefinitionInBlock

module SaxBenchHandlers
  class NullHandler < Moxml::SAX::Handler
    def on_start_element(_name, _attrs = {}, _namespaces = {}); end

    def on_end_element(_name); end

    def on_characters(_text); end
  end

  class RecordWalkHandler < Moxml::SAX::Handler
    attr_reader :elements

    def initialize
      super
      @elements = 0
    end

    # The hot-loop shape: walk the records, materialize one name per
    # element (the #1298 target — consumer-chosen allocations).
    def on_sax_records(table)
      i = 0
      while i < table.count
        @elements += 1 if table.kind(i).zero? && table.view(i)
        i += 1
      end
      :claimed
    end
  end
end

CTX = Moxml.new(:leptris).freeze # rubocop:disable Lint/ConstantDefinitionInBlock
BRIDGE = Moxml::Adapter::Leptris::LeptrisSAXBridge # rubocop:disable Lint/ConstantDefinitionInBlock

def allocations
  GC.start
  before = GC.stat(:total_allocated_objects)
  GC.disable
  yield
  GC.enable
  GC.stat(:total_allocated_objects) - before
end

def cpu_micros
  GC.start
  t0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID, :microsecond)
  yield
  Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID, :microsecond) - t0
end

# warm both lanes
handler = SaxBenchHandlers::NullHandler.new
3.times { DOCS.each { |doc| Moxml::Adapter::Leptris.sax_parse(doc, handler) } }
3.times { DOCS.each { |doc| Leptris::XML::SAX::Parser.new(BRIDGE.new(handler)).parse(doc) } }
walker = SaxBenchHandlers::RecordWalkHandler.new
3.times { DOCS.each { |doc| Moxml::Adapter::Leptris.sax_parse(doc, walker) } }

recorder_allocs = allocations do
  DOCS.each { |doc| Leptris::XML::SAX::Parser.new(BRIDGE.new(handler)).parse(doc) }
end
replay_allocs = allocations do
  DOCS.each { |doc| Moxml::Adapter::Leptris.sax_parse(doc, handler) }
end
walk_allocs = allocations do
  DOCS.each { |doc| Moxml::Adapter::Leptris.sax_parse(doc, walker) }
end

replay_time = cpu_micros { 5.times { DOCS.each { |doc| Moxml::Adapter::Leptris.sax_parse(doc, handler) } } }
recorder_time = cpu_micros { 5.times { DOCS.each { |doc| Leptris::XML::SAX::Parser.new(BRIDGE.new(handler)).parse(doc) } } }
walk_time = cpu_micros { 5.times { DOCS.each { |doc| Moxml::Adapter::Leptris.sax_parse(doc, walker) } } }

puts format("recorder           %<allocs>6d allocs  %<time>6dµs", allocs: recorder_allocs, time: recorder_time / 5)
puts format("drain replay       %<allocs>6d allocs  %<time>6dµs", allocs: replay_allocs, time: replay_time / 5)
puts format("drain records-walk %<allocs>6d allocs  %<time>6dµs", allocs: walk_allocs, time: walk_time / 5)
puts "(#{walker.elements} elements walked cumulatively; 452 per rep)"

if ENV["LEPTRIS_BENCH_LOCK"]
  if walk_allocs >= recorder_allocs / 2
    warn "LEPTRIS_BENCH_LOCK: records-walk allocs (#{walk_allocs}) " \
         "not under half the recorder's (#{recorder_allocs}) — the " \
         "#1298 win regressed"
    exit 1
  end
  puts "lock: records-walk under half the recorder's allocations ✓"
end
