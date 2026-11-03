# frozen_string_literal: true

# moxml#520 calibration: raw engine parse vs moxml adapter parse, per engine,
# on the plateau_all_packages_export.xmi corpus (103 MB).
# Usage: ruby calibrate.rb raw-lep | raw-noko | mox-lep | mox-noko

require "pathname"
CORPUS = "/Users/mulgogi/src/mn/mn-samples-plateau-cg3/sources/xmi/plateau_all_packages_export.xmi"
CONTENT = File.read(CORPUS, mode: "rb").freeze

def measure(label)
  GC.start
  before = GC.stat(:total_allocated_objects)
  rss0 = `ps -o rss= -p #{Process.pid}`.to_i
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  rss1 = `ps -o rss= -p #{Process.pid}`.to_i
  after = GC.stat(:total_allocated_objects)
  puts format(
    "%<label>-24s %<dt>7.2fs  allocs %<allocs>9.2fM  rss %<rss0>6.0f -> %<rss1>6.0f MB",
    label: label, dt: dt, allocs: (after - before) / 1e6,
    rss0: rss0 / 1024.0, rss1: rss1 / 1024.0
  )
  result
end

case ARGV[0]
when "raw-lep"
  require "fiddle"
  require "fiddle/import"
  module Lep
    extend Fiddle::Importer

    dlload File.expand_path("~/src/leptris/leptris-rs/.local-lib/libleptris.dylib")
    extern "void *leptris_parse_string(const char *, size_t, int *)"
    extern "void leptris_document_free(void *)"
  end
  measure("raw libleptris parse") do
    st = [0].pack("l").freeze
    buf = "#{CONTENT}\0"
    doc = Lep.leptris_parse_string(buf, CONTENT.bytesize, st)
    raise "parse failed status #{st.unpack1('l')}" if doc.null?

    Lep.leptris_document_free(doc)
  end
when "raw-noko"
  require "nokogiri"
  measure("raw nokogiri parse") do
    d = Nokogiri::XML(CONTENT, &:noblanks)
    raise "no root" unless d.root

    nil
  end
when "mox-lep", "mox-noko"
  require "moxml"
  adapter = ARGV[0] == "mox-lep" ? :leptris : :nokogiri
  ctx = Moxml.new(adapter)
  measure("moxml #{adapter} parse") do
    doc = ctx.parse(CONTENT)
    raise "no root" unless doc.root

    doc
  end
when "walk-lep", "walk-noko"
  require "moxml"
  adapter = ARGV[0] == "walk-lep" ? :leptris : :nokogiri
  ctx = Moxml.new(adapter)
  doc = ctx.parse(CONTENT)
  measure("moxml #{adapter} walk") do
    seen = 0
    stack = [doc.root]
    while (el = stack.pop)
      seen += 1
      el.name
      el.attributes.each do |k, a|
        k
        a&.value
      end
      el.text
      el.children.each do |c|
        stack << c if c.is_a?(Moxml::Element)
      end
    end
    puts "  visited #{seen} elements"
  end
else
  abort "usage: calibrate.rb raw-lep|raw-noko|mox-lep|mox-noko"
end
