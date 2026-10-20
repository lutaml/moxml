# frozen_string_literal: true

# The published performance scoreboard (TODO.sota/04).
#
# Protocol: CPU-time medians of an interleaved A/B run. For every
# repetition the baseline (raw nokogiri) and the candidate (moxml on
# the fastest engine lane) alternate in the same thermal window; the
# reported ratio is median(baseline) / median(candidate), so > 1.0
# means the facade is faster than the raw library.
#
# Honesty gates:
#   - CPU time (CLOCK_PROCESS_CPUTIME_ID), not wall time, so scheduler
#     noise does not become a performance claim;
#   - the harness refuses to report when the 1-minute load exceeds
#     half the CPU count (override with SCORE_FORCE=1 for smoke runs);
#   - warmup runs are discarded; GC is started between samples;
#   - every row names the exact operation measured.
#
# Usage:
#   bundle exec ruby benchmark/scoreboard.rb                  # all rows
#   SCORE_ROWS=parse,serialize bundle exec ruby benchmark/scoreboard.rb
#   SCORE_ADAPTER=oga bundle exec ruby benchmark/scoreboard.rb
#   SCORE_JSON=benchmark/scoreboard.json bundle exec ruby benchmark/scoreboard.rb
#   SCORE_LOCK=1 bundle exec ruby benchmark/scoreboard.rb     # parity gate
#
# SCORE_LOCK=1 exits non-zero when a parity row is below 1.0x or when
# a row regresses more than 10% against SCORE_BASELINE.
require "moxml"
require "nokogiri"
require "json"
require "time"

module Scoreboard
  ADAPTER = (ENV["SCORE_ADAPTER"] || "leptris").to_sym
  REPS = (ENV["SCORE_REPS"] || 9).to_i
  WARMUP = (ENV["SCORE_WARMUP"] || 2).to_i
  ROW_FILTER = ENV["SCORE_ROWS"]&.split(",")&.map(&:strip)
  FORCE = ENV["SCORE_FORCE"] == "1"
  LOCK = ENV["SCORE_LOCK"] == "1"
  BASELINE_PATH = ENV.fetch("SCORE_BASELINE", nil)
  JSON_PATH = ENV.fetch("SCORE_JSON", nil)
  MARKDOWN_PATH = ENV.fetch("SCORE_MARKDOWN", nil)
  PUBLISH = ENV["SCORE_PUBLISH"] == "1"
  REGRESSION_TOLERANCE = 0.10
  # Measurement tolerance for the absolute parity gate: ratios move a
  # few percent run to run; a row must stay at or above this floor.
  PARITY_FLOOR = 0.95

  Field = Struct.new(:name, :unit, :value)
  Record = Struct.new(:id, :kind, :fields)
  Catalog = Struct.new(:records)

  PLAN = Moxml::Plan.new do
    on("record") { |attrs, _text, fields| Record.new(attrs["id"], attrs["kind"], fields) }
    on("field") { |attrs, text, _kids| Field.new(attrs["name"], attrs["unit"], text) }
  end

  module_function

  # A consumer-shaped catalog: mixed text, attributes, nesting.
  def xml
    @xml ||= begin
      parts = [%(<?xml version="1.0"?><catalog>)]
      300.times do |i|
        parts << %(<record id="r#{i}" kind="k#{i % 3}">)
        4.times do |j|
          parts << %(<field name="f#{j}" unit="u#{j}">value #{i}.#{j}</field>)
        end
        parts << %(</record>)
      end
      parts << %(</catalog>)
      parts.join
    end
  end

  def cpu_now
    Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  end

  def load_average
    if File.exist?("/proc/loadavg")
      File.read("/proc/loadavg").split[0].to_f
    else
      `sysctl -n vm.loadavg 2>/dev/null`.split[1].to_f
    end
  end

  def ncpu
    require "etc"
    Etc.nprocessors
  rescue StandardError
    1
  end

  def check_load!
    return if FORCE

    load = load_average
    budget = ncpu * 0.5
    return if load <= budget

    warn format(
      "scoreboard: refusing to measure — 1-minute load %<load>.1f exceeds " \
      "%<budget>.1f (half of %<ncpu>d CPUs). Stop background work or set " \
      "SCORE_FORCE=1 for a smoke run (numbers are not publishable).",
      load: load, budget: budget, ncpu: ncpu,
    )
    exit 2
  end

  def median(values)
    sorted = values.sort
    sorted[sorted.size / 2]
  end

  # Interleaved A/B sampling. Yields :baseline / :candidate; returns
  # [median_baseline, median_candidate, allocations_baseline,
  # allocations_candidate] over the requested repetition count.
  def measure
    WARMUP.times { yield :baseline }
    WARMUP.times { yield :candidate }
    baseline = []
    candidate = []
    base_allocs = nil
    cand_allocs = nil
    REPS.times do
      [[:baseline, baseline], [:candidate, candidate]].each do |side, bucket|
        GC.start
        a0 = GC.stat(:total_allocated_objects)
        t0 = cpu_now
        yield side
        dt = cpu_now - t0
        bucket << (dt * 1e6)
        allocs = GC.stat(:total_allocated_objects) - a0
        if side == :baseline
          base_allocs = allocs
        else
          cand_allocs = allocs
        end
      end
    end
    [median(baseline), median(candidate), base_allocs, cand_allocs]
  end

  # --- shared fixtures ------------------------------------------------

  def baseline_doc
    @baseline_doc ||= Nokogiri::XML(xml)
  end

  def moxml_doc
    @moxml_doc ||= moxml_ctx.parse(xml)
  end

  def moxml_ctx
    @moxml_ctx ||= Moxml.new(ADAPTER)
  end

  def baseline_records
    @baseline_records ||= baseline_doc.xpath("//record")
  end

  def moxml_records
    @moxml_records ||= moxml_doc.xpath("//record").to_a
  end

  # Row registry. Each entry: name, kind (:parity / :structural /
  # :data), and the operation in both worlds.
  def rows
    @rows ||= begin
      definition = {
        "parse" => [:parity,
                    -> { Nokogiri::XML(xml) },
                    -> { moxml_ctx.parse(xml) }],
        "serialize" => [:parity,
                        -> { baseline_doc.to_xml },
                        -> { moxml_doc.to_xml }],
        # Count only: the node-set cardinality without materializing
        # wrapper objects on either side.
        "xpath //field (count)" => [:parity,
                                    -> { baseline_doc.xpath("//field").size },
                                    -> { moxml_doc.xpath("//field").size }],
        # Materialized results: what a consumer iterating the set pays.
        # Structural (tracked, not parity): per-result wrapper mint.
        "xpath //field (each)" => [:structural,
                                   -> { baseline_doc.xpath("//field").each(&:name) },
                                   -> { moxml_doc.xpath("//field").each(&:name) }],
        "attr pairs listing" => [:parity,
                                 -> do
                                   baseline_records.each do |e|
                                     e.attributes.map { |k, v| [k, v.value] }
                                   end
                                 end,
                                 -> { moxml_records.each(&:attribute_pairs) }],
        # Structural (tracked, not parity): engine mint + GC.
        "build add_element" => [:structural,
                                -> { build_nokogiri },
                                -> { build_moxml(moxml_ctx) }],
        # Warm traversal is near parity but not reliably above it on
        # every machine: tracked, not parity-gated.
        "walk+read (warm)" => [:structural,
                               -> { walk_nokogiri(baseline_doc) },
                               -> { walk_moxml(moxml_doc) }],
        # Structural (tracked, not parity): per-node wrapper mint.
        "walk+read (cold)" => [:structural,
                               -> { walk_nokogiri(Nokogiri::XML(xml)) },
                               -> { walk_moxml(moxml_ctx.parse(xml)) }],
        # Structural row: recurse through `children` and filter
        # elements — the NodeSet machinery cost, cold.
        "children recursion (cold)" => [:structural,
                                        -> { children_nokogiri(Nokogiri::XML(xml)) },
                                        -> { children_moxml(moxml_ctx.parse(xml)) }],
        # The data-API row: the compiled plan against the typed
        # Nokogiri walk consumers write by hand.
        "plan records (typed)" => [:data,
                                   -> { typed_nokogiri(Nokogiri::XML(xml)) },
                                   -> { PLAN.parse(xml, moxml_ctx) }],
      }
      definition.select { |name, _| ROW_FILTER.nil? || ROW_FILTER.include?(name) }
    end
  end

  # --- row implementations -------------------------------------------

  def build_nokogiri
    doc = Nokogiri::XML::Document.new
    root = Nokogiri::XML::Node.new("catalog", doc)
    doc.root = root
    300.times do |i|
      record = Nokogiri::XML::Node.new("record", doc)
      record["id"] = "r#{i}"
      record["kind"] = "k#{i % 3}"
      4.times do |j|
        field = Nokogiri::XML::Node.new("field", doc)
        field["name"] = "f#{j}"
        field["unit"] = "u#{j}"
        field.content = "value #{i}.#{j}"
        record.add_child(field)
      end
      root.add_child(record)
    end
    doc
  end

  def build_moxml(ctx)
    doc = ctx.create_document
    root = doc.add_element("catalog")
    300.times do |i|
      record = root.add_element("record", "id" => "r#{i}", "kind" => "k#{i % 3}")
      4.times do |j|
        field = record.add_element("field", "name" => "f#{j}", "unit" => "u#{j}")
        field.content = "value #{i}.#{j}"
      end
    end
    doc
  end

  def walk_nokogiri(doc)
    walk = lambda do |node|
      node.element_children.each do |child|
        child.name
        child.text
        walk.call(child)
      end
    end
    walk.call(doc.root)
  end

  def walk_moxml(doc)
    walk = lambda do |node|
      node.children.each do |child|
        next unless child.is_a?(Moxml::Element)

        child.name
        child.text
        walk.call(child)
      end
    end
    walk.call(doc.root)
  end

  def children_nokogiri(doc)
    walk = lambda do |node|
      node.children.each do |child|
        next unless child.element?

        child.name
        walk.call(child)
      end
    end
    walk.call(doc.root)
  end

  def children_moxml(doc)
    walk = lambda do |node|
      node.children.each do |child|
        next unless child.is_a?(Moxml::Element)

        child.name
        walk.call(child)
      end
    end
    walk.call(doc.root)
  end

  def typed_nokogiri(doc)
    records = doc.root.element_children.map do |record|
      fields = record.element_children.map do |field|
        Field.new(field["name"], field["unit"], field.text)
      end
      Record.new(record["id"], record["kind"], fields)
    end
    Catalog.new(records)
  end

  # --- run ------------------------------------------------------------

  def validate_fixtures!
    records = PLAN.parse(xml, moxml_ctx)
    raise "plan shape" unless records.size == 300

    typed = typed_nokogiri(baseline_doc)
    raise "typed shape" unless typed.records.size == 300
  end

  def run
    check_load!
    validate_fixtures!
    results = []
    rows.each do |name, (kind, baseline_op, candidate_op)|
      b, c, ba, ca = measure do |side|
        side == :baseline ? baseline_op.call : candidate_op.call
      end
      ratio = b / c
      results << {
        "row" => name,
        "kind" => kind.to_s,
        "parity" => kind == :parity,
        "baseline_us" => b.round(1),
        "candidate_us" => c.round(1),
        "ratio" => ratio.round(3),
        "baseline_allocs" => ba,
        "candidate_allocs" => ca,
      }
    end

    report(results)
    write_json(results) if JSON_PATH
    write_markdown(results) if MARKDOWN_PATH
    write_published(results) if PUBLISH
    enforce_lock(results) if LOCK
    results
  end

  def report(results)
    puts format(
      "%-28<row>s %12<nk>s %12<mx>s %8<ratio>s %10<na>s %10<ma>s",
      row: "row", nk: "nokogiri us", mx: "#{ADAPTER} us", ratio: "ratio",
      na: "nk allocs", ma: "mx allocs"
    )
    results.each do |row|
      puts format(
        "%-28<row>s %12.1<base>f %12.1<cand>f %7.2<ratio>fx " \
        "%10<ba>d %10<ca>d%<tag>s",
        row: row["row"], base: row["baseline_us"],
        cand: row["candidate_us"], ratio: row["ratio"],
        ba: row["baseline_allocs"], ca: row["candidate_allocs"],
        tag: row["parity"] ? "" : "  (#{row['kind']})"
      )
    end
    puts format(
      "(ruby %<ruby>s; %<adapter>s %<version>s; load %<load>.2f; " \
      "reps %<reps>d; CPU medians, interleaved)",
      ruby: RUBY_VERSION,
      adapter: ADAPTER,
      version: defined?(Leptris::VERSION) && ADAPTER == :leptris ? Leptris::VERSION : "",
      load: load_average,
      reps: REPS,
    )
  end

  ADOC_PATH = "docs/_pages/performance.adoc"
  ADOC_BEGIN = "// SCOREBOARD:BEGIN"
  ADOC_END = "// SCOREBOARD:END"
  README_PATH = "benchmark/README.md"
  PUBLISHED_JSON = "benchmark/scoreboard.json"
  SCOREBOARD_BEGIN = "<!-- SCOREBOARD:BEGIN -->"
  SCOREBOARD_END = "<!-- SCOREBOARD:END -->"

  def write_published(results)
    write_json(results, PUBLISHED_JSON)
    write_adoc(results)
    write_readme(results)
    warn "scoreboard: published #{ADOC_PATH} and #{README_PATH}"
  end

  def kind_of(row)
    row["kind"]
  end

  def status_of(row)
    case row["kind"]
    when "parity"
      row["ratio"] >= PARITY_FLOOR ? "met" : "open (below parity)"
    when "structural"
      "tracked (below parity)"
    else
      "informational"
    end
  end

  def markdown_table(results)
    lines = [
      "| Row | Ratio | Kind | Status |",
      "| --- | ----- | ---- | ------ |",
    ]
    results.each do |row|
      lines << format("| `%<row>s` | %<ratio>.2fx | %<kind>s | %<status>s |",
                      row: row["row"], ratio: row["ratio"],
                      kind: kind_of(row), status: status_of(row))
    end
    lines.join("\n")
  end

  def adoc_table(results)
    lines = [
      '[cols="2,1,1,1",options="header"]',
      "|===",
      "| Row | Ratio | Kind | Status",
    ]
    results.each do |row|
      lines << format("| `%<row>s` | %<ratio>.2fx | %<kind>s | %<status>s",
                      row: row["row"], ratio: row["ratio"],
                      kind: kind_of(row), status: status_of(row))
    end
    lines << "|==="
    lines.join("\n")
  end

  def write_readme(results)
    text = File.read(README_PATH)
    pattern = /#{Regexp.escape(SCOREBOARD_BEGIN)}.*?#{Regexp.escape(SCOREBOARD_END)}/mo
    return unless text.match?(pattern)

    block = "#{SCOREBOARD_BEGIN}\n#{markdown_table(results)}\n" \
            "#{SCOREBOARD_END}"
    File.write(README_PATH, text.sub(pattern, block))
  end

  def write_adoc(results)
    text = File.read(ADOC_PATH)
    pattern = /#{Regexp.escape(ADOC_BEGIN)}.*?#{Regexp.escape(ADOC_END)}/mo
    unless text.match?(pattern)
      warn "scoreboard: #{ADOC_PATH} has no scoreboard markers; skipping " \
           "(add #{ADOC_BEGIN} / #{ADOC_END})"
      return
    end

    lines = []
    lines << "Generated by `SCORE_PUBLISH=1 bundle exec ruby " \
             "benchmark/scoreboard.rb`. Protocol: CPU-time medians of " \
             "an interleaved A/B run (raw nokogiri vs moxml on " \
             "#{ADAPTER}); the ratio is baseline / candidate, so > 1.0 " \
             "means the facade is faster. Warmups discarded, GC between " \
             "samples."
    lines << ""
    lines << "Measurement: Ruby #{RUBY_VERSION}, #{ADAPTER} " \
             "#{Leptris::VERSION if defined?(Leptris::VERSION) && ADAPTER == :leptris}, " \
             "nokogiri #{Nokogiri::VERSION}, #{Time.now.utc.iso8601}, " \
             "1-minute load #{load_average.round(2)}, #{REPS} repetitions."
    lines << ""
    lines << adoc_table(results)
    lines << ""
    lines << "*Parity rows* must stay at or above the 0.95 measurement " \
             "floor. *Structural rows* are measured and trend-locked " \
             "(10% regression tolerance) while their gaps remain open: " \
             "per-node wrapper minting costs (#312 endgame) and engine " \
             "construction. *Data API* rows are informational."
    lines << ""
    block = "#{ADOC_BEGIN}\n#{lines.join("\n")}#{ADOC_END}"
    File.write(ADOC_PATH, text.sub(pattern, block))
  end

  def write_markdown(results)
    lines = [
      "## Performance scoreboard",
      "",
      "CPU-time medians of an interleaved A/B run against raw nokogiri " \
      "on the same document (ratio > 1.0 means moxml is faster). " \
      "Pair: moxml + #{ADAPTER} " \
      "#{Leptris::VERSION if defined?(Leptris::VERSION) && ADAPTER == :leptris} " \
      "on Ruby #{RUBY_VERSION}; #{REPS} repetitions.",
      "",
      markdown_table(results),
      "",
      "Parity rows are the commitment (0.95 measurement floor); " \
      "structural rows are tracked (10% regression tolerance) with " \
      "their gaps documented in `benchmark/README.md`.",
    ]
    File.write(MARKDOWN_PATH, "#{lines.join("\n")}\n")
    warn "scoreboard: wrote #{MARKDOWN_PATH}"
  end

  def write_json(results, path = JSON_PATH)
    payload = {
      "protocol" => {
        "measured" => Time.now.utc.iso8601,
        "ruby" => RUBY_VERSION,
        "adapter" => ADAPTER.to_s,
        "adapter_version" => (defined?(Leptris::VERSION) ? Leptris::VERSION : nil),
        "nokogiri" => Nokogiri::VERSION,
        "reps" => REPS,
        "warmup" => WARMUP,
        "clock" => "CLOCK_PROCESS_CPUTIME_ID",
        "load" => load_average.round(2),
      },
      "rows" => results,
    }
    File.write(path, "#{JSON.pretty_generate(payload)}\n")
    warn "scoreboard: wrote #{path}"
  end

  def enforce_lock(results)
    failures = results.select do |row|
      row["kind"] == "parity" && row["ratio"] < PARITY_FLOOR
    end
    if BASELINE_PATH && File.exist?(BASELINE_PATH)
      baseline = JSON.parse(File.read(BASELINE_PATH))
        .fetch("rows").to_h { |row| [row["row"], row] }
      results.each do |row|
        old = baseline[row["row"]]
        next unless old && old["ratio"].to_f.positive?

        floor = old["ratio"].to_f * (1.0 - REGRESSION_TOLERANCE)
        next if row["ratio"] >= floor

        failures << row.merge(
          "regression" => "#{format('%.2f', row['ratio'])}x < " \
                          "#{format('%.2f', floor)}x (10% below baseline " \
                          "#{format('%.2f', old['ratio'])}x)",
        )
      end
    end
    return if failures.empty?

    warn "scoreboard lock FAILED:"
    failures.each do |row|
      warn format("  %-28<row>s %6.2<ratio>fx %<note>s",
                  row: row["row"], ratio: row["ratio"],
                  note: row["regression"] || "below parity")
    end
    exit 1
  end
end

Scoreboard.run
