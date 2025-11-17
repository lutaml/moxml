# frozen_string_literal: true

require "benchmark"
require "benchmark/ips"
require_relative "../lib/moxml"
require "rbconfig"

# Benchmark Report Generator for Moxml Adapters
class MoxmlBenchmarkReport
  ADAPTERS = %i[nokogiri oga rexml libxml ox].freeze

  # Test XML documents of varying complexity
  SIMPLE_XML = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <root>
      <item id="1">Simple</item>
    </root>
  XML

  MEDIUM_XML = lambda {
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <library xmlns="http://example.org/library" xmlns:dc="http://purl.org/dc/elements/1.1/">
    XML
    50.times do |i|
      xml += <<~ITEM
        <book id="book-#{i}">
          <dc:title>Book Title #{i}</dc:title>
          <dc:author>Author #{i}</dc:author>
          <published year="#{2020 + (i % 5)}"/>
          <description>A detailed description of book #{i} with some content.</description>
        </book>
      ITEM
    end
    "#{xml}</library>"
  }.call

  LARGE_XML = lambda {
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <catalog xmlns="http://example.org/catalog">
    XML
    500.times do |i|
      xml += <<~ITEM
        <product id="prod-#{i}" category="cat-#{i % 10}">
          <name>Product #{i}</name>
          <price currency="USD">#{(i % 100) + 9.99}</price>
          <stock>#{i % 1000}</stock>
          <description>Description for product #{i}</description>
          <metadata>
            <created>2024-01-#{(i % 28) + 1}</created>
            <updated>2024-10-#{(i % 28) + 1}</updated>
          </metadata>
        </product>
      ITEM
    end
    "#{xml}</catalog>"
  }.call

  COMPLEX_NESTED_XML = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <root xmlns:a="http://a.org" xmlns:b="http://b.org">
      <a:level1>
        <b:level2>
          <a:level3>
            <b:level4>
              <a:level5>Deep content</a:level5>
            </b:level4>
          </a:level3>
        </b:level2>
      </a:level1>
    </root>
  XML

  def initialize
    @results = {}
    @errors = {}
    @timestamp = Time.now
  end

  def run
    puts "=" * 80
    puts "Moxml Adapter Benchmark Report Generator"
    puts "=" * 80
    puts ""

    ADAPTERS.each do |adapter|
      puts "\nBenchmarking #{adapter.to_s.upcase} adapter..."
      benchmark_adapter(adapter)
    end

    generate_report
  end

  private

  def benchmark_adapter(adapter_name)
    @results[adapter_name] = {}
    @errors[adapter_name] = []

    begin
      context = Moxml.new do |config|
        config.adapter = adapter_name
      end

      # Parsing benchmarks
      @results[adapter_name][:parse_simple] = benchmark_parse(context, SIMPLE_XML)
      @results[adapter_name][:parse_medium] = benchmark_parse(context, MEDIUM_XML)
      @results[adapter_name][:parse_large] = benchmark_parse(context, LARGE_XML)
      @results[adapter_name][:parse_complex] = benchmark_parse(context, COMPLEX_NESTED_XML)

      # Serialization benchmarks
      context.parse(MEDIUM_XML)
      @results[adapter_name][:serialize_simple] = benchmark_serialize(context, SIMPLE_XML)
      @results[adapter_name][:serialize_medium] = benchmark_serialize(context, MEDIUM_XML)
      @results[adapter_name][:serialize_large] = benchmark_serialize(context, LARGE_XML)

      # XPath benchmarks
      @results[adapter_name][:xpath_simple] = benchmark_xpath_simple(context, MEDIUM_XML)
      @results[adapter_name][:xpath_complex] = benchmark_xpath_complex(context, MEDIUM_XML)
      @results[adapter_name][:xpath_namespace] = benchmark_xpath_namespace(context, MEDIUM_XML)

      # Memory benchmarks
      @results[adapter_name][:memory_medium] = benchmark_memory(context, MEDIUM_XML)
      @results[adapter_name][:memory_large] = benchmark_memory(context, LARGE_XML)

      puts "  ✓ #{adapter_name} benchmarks completed"
    rescue StandardError => e
      @errors[adapter_name] << "Failed to benchmark: #{e.message}"
      puts "  ✗ #{adapter_name} benchmarks failed: #{e.message}"
    end
  end

  def benchmark_parse(context, xml)
    result = nil
    Benchmark.ips do |x|
      x.config(time: 2, warmup: 1)
      x.report("parse") { result = context.parse(xml) }
    end.entries.first.ips.round(2)
  rescue StandardError => e
    @errors[context.config.adapter_name] << "Parse error: #{e.message}"
    0.0
  end

  def benchmark_serialize(context, xml)
    doc = context.parse(xml)
    Benchmark.ips do |x|
      x.config(time: 2, warmup: 1)
      x.report("serialize") { doc.to_xml }
    end.entries.first.ips.round(2)
  rescue StandardError => e
    @errors[context.config.adapter_name] << "Serialize error: #{e.message}"
    0.0
  end

  def benchmark_xpath_simple(context, xml)
    doc = context.parse(xml)
    Benchmark.ips do |x|
      x.config(time: 2, warmup: 1)
      x.report("xpath_simple") { doc.xpath("//book") }
    end.entries.first.ips.round(2)
  rescue StandardError => e
    @errors[context.config.adapter_name] << "XPath simple error: #{e.message}"
    0.0
  end

  def benchmark_xpath_complex(context, xml)
    doc = context.parse(xml)
    Benchmark.ips do |x|
      x.config(time: 2, warmup: 1)
      x.report("xpath_complex") { doc.xpath("//book[@id]") }
    end.entries.first.ips.round(2)
  rescue StandardError => e
    @errors[context.config.adapter_name] << "XPath complex error: #{e.message}"
    0.0
  end

  def benchmark_xpath_namespace(context, xml)
    doc = context.parse(xml)
    namespaces = { "dc" => "http://purl.org/dc/elements/1.1/" }
    Benchmark.ips do |x|
      x.config(time: 2, warmup: 1)
      x.report("xpath_ns") { doc.xpath("//dc:title", namespaces) }
    end.entries.first.ips.round(2)
  rescue StandardError => e
    @errors[context.config.adapter_name] << "XPath namespace error: #{e.message}"
    0.0
  end

  def benchmark_memory(context, xml)
    before = get_memory_usage
    10.times { context.parse(xml) }
    after = get_memory_usage
    ((after - before) / 10.0).round(2)
  rescue StandardError => e
    @errors[context.config.adapter_name] << "Memory error: #{e.message}"
    0.0
  end

  def get_memory_usage
    # Get memory usage in MB
    if RUBY_PLATFORM =~ /darwin/
      `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
    elsif RUBY_PLATFORM =~ /linux/
      `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
    else
      0.0 # Not supported on this platform
    end
  end

  def calculate_grade(adapter_name)
    results = @results[adapter_name]
    return "N/A" if results.empty? || @errors[adapter_name].any?

    # Weighted scoring
    score = 0
    score += normalize_score(results[:parse_medium], 100, 2000) * 30 # 30% weight
    score += normalize_score(results[:serialize_medium], 100, 1500) * 25 # 25% weight
    score += normalize_score(results[:xpath_simple], 100, 2000) * 20 # 20% weight
    score += normalize_score(results[:memory_medium], 5, 50, inverse: true) * 15 # 15% weight (lower is better)
    score += (@errors[adapter_name].empty? ? 10 : 0) # 10% reliability

    case score
    when 90..100 then "A+"
    when 80..89 then "A"
    when 70..79 then "B+"
    when 60..69 then "B"
    when 50..59 then "C"
    else "D"
    end
  end

  def normalize_score(value, min, max, inverse: false)
    return 0 if value.nil? || value.zero?

    normalized = ((value - min).to_f / (max - min) * 100).clamp(0, 100)
    inverse ? (100 - normalized) : normalized
  end

  def memory_stars(mb)
    case mb
    when 0..10 then "⭐⭐⭐⭐⭐"
    when 10..20 then "⭐⭐⭐⭐"
    when 20..40 then "⭐⭐⭐"
    when 40..80 then "⭐⭐"
    else "⭐"
    end
  end

  def generate_report
    File.open("benchmarks/PERFORMANCE_REPORT.md", "w") do |f|
      write_header(f)
      write_summary_table(f)
      write_detailed_results(f)
      write_recommendations(f)
      write_environment_details(f)
      write_errors(f) if @errors.values.any?(&:any?)
    end

    puts "\n#{"=" * 80}"
    puts "Report generated: benchmarks/PERFORMANCE_REPORT.md"
    puts "=" * 80
  end

  def write_header(f)
    f.puts "# Moxml Adapter Performance Benchmarks"
    f.puts ""
    f.puts "Generated: #{@timestamp.strftime("%Y-%m-%d %H:%M:%S %Z")}"
    f.puts ""
    f.puts "This report compares the performance of all Moxml adapters across various"
    f.puts "benchmarks including parsing, serialization, XPath queries, and memory usage."
    f.puts ""
  end

  def write_summary_table(f)
    f.puts "## Summary"
    f.puts ""
    f.puts "| Adapter | Parse (ips) | Serialize (ips) | XPath (ips) | Memory (MB) | Grade |"
    f.puts "|---------|-------------|-----------------|-------------|-------------|-------|"

    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      results = @results[adapter]
      parse_ips = results[:parse_medium]&.round(0) || "N/A"
      serialize_ips = results[:serialize_medium]&.round(0) || "N/A"
      xpath_ips = results[:xpath_simple]&.round(0) || "N/A"
      memory = results[:memory_medium]&.round(1) || "N/A"
      stars = memory.is_a?(Numeric) ? memory_stars(memory) : "N/A"
      grade = calculate_grade(adapter)

      f.puts "| #{adapter.to_s.capitalize} | #{parse_ips} | #{serialize_ips} | #{xpath_ips} | #{memory} #{stars} | #{grade} |"
    end
    f.puts ""
  end

  def write_detailed_results(f)
    f.puts "## Detailed Results"
    f.puts ""

    # Parsing benchmarks
    f.puts "### Parsing Performance"
    f.puts ""
    f.puts "| Adapter | Simple XML | Medium XML | Large XML | Complex Nested |"
    f.puts "|---------|------------|------------|-----------|----------------|"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      r = @results[adapter]
      f.puts "| #{adapter.to_s.capitalize} | #{r[:parse_simple]&.round(0) || "N/A"} ips | #{r[:parse_medium]&.round(0) || "N/A"} ips | #{r[:parse_large]&.round(0) || "N/A"} ips | #{r[:parse_complex]&.round(0) || "N/A"} ips |"
    end
    f.puts ""
    f.puts "**Document Sizes:**"
    f.puts "- Simple: #{SIMPLE_XML.bytesize} bytes"
    f.puts "- Medium: #{MEDIUM_XML.bytesize} bytes (50 book elements with namespaces)"
    f.puts "- Large: #{LARGE_XML.bytesize} bytes (500 product elements)"
    f.puts "- Complex: #{COMPLEX_NESTED_XML.bytesize} bytes (deeply nested with namespaces)"
    f.puts ""

    # Serialization benchmarks
    f.puts "### Serialization Performance"
    f.puts ""
    f.puts "| Adapter | Simple XML | Medium XML | Large XML |"
    f.puts "|---------|------------|------------|-----------|"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      r = @results[adapter]
      f.puts "| #{adapter.to_s.capitalize} | #{r[:serialize_simple]&.round(0) || "N/A"} ips | #{r[:serialize_medium]&.round(0) || "N/A"} ips | #{r[:serialize_large]&.round(0) || "N/A"} ips |"
    end
    f.puts ""

    # XPath benchmarks
    f.puts "### XPath Query Performance"
    f.puts ""
    f.puts "| Adapter | Simple Query | Complex Query | Namespace Query |"
    f.puts "|---------|--------------|---------------|-----------------|"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      r = @results[adapter]
      f.puts "| #{adapter.to_s.capitalize} | #{r[:xpath_simple]&.round(0) || "N/A"} ips | #{r[:xpath_complex]&.round(0) || "N/A"} ips | #{r[:xpath_namespace]&.round(0) || "N/A"} ips |"
    end
    f.puts ""
    f.puts "**Query Types:**"
    f.puts "- Simple: `//book` (find all book elements)"
    f.puts "- Complex: `//book[@id]` (find books with id attribute)"
    f.puts "- Namespace: `//dc:title` (find elements in dc namespace)"
    f.puts ""

    # Memory benchmarks
    f.puts "### Memory Usage"
    f.puts ""
    f.puts "| Adapter | Medium Document | Large Document |"
    f.puts "|---------|-----------------|----------------|"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      r = @results[adapter]
      medium_mem = r[:memory_medium]&.round(1) || "N/A"
      large_mem = r[:memory_large]&.round(1) || "N/A"
      f.puts "| #{adapter.to_s.capitalize} | #{medium_mem} MB | #{large_mem} MB |"
    end
    f.puts ""
    f.puts "**Note:** Memory measurements show average increase per document parse."
    f.puts ""

    # Performance chart (ASCII art)
    write_performance_chart(f)
  end

  def write_performance_chart(f)
    f.puts "### Performance Visualization"
    f.puts ""
    f.puts "```"
    f.puts "Relative Performance (Higher is Better)"
    f.puts ""

    max_parse = @results.values.map { |r| r[:parse_medium] || 0 }.max
    max_serialize = @results.values.map { |r| r[:serialize_medium] || 0 }.max
    max_xpath = @results.values.map { |r| r[:xpath_simple] || 0 }.max

    f.puts "Parsing (Medium XML):"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      value = @results[adapter][:parse_medium] || 0
      bar_length = (value.to_f / max_parse * 50).to_i
      f.puts "  #{adapter.to_s.capitalize.ljust(10)} #{"█" * bar_length} #{value.round(0)} ips"
    end
    f.puts ""

    f.puts "Serialization (Medium XML):"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      value = @results[adapter][:serialize_medium] || 0
      bar_length = (value.to_f / max_serialize * 50).to_i
      f.puts "  #{adapter.to_s.capitalize.ljust(10)} #{"█" * bar_length} #{value.round(0)} ips"
    end
    f.puts ""

    f.puts "XPath Queries (Simple):"
    ADAPTERS.each do |adapter|
      next if @results[adapter].empty?

      value = @results[adapter][:xpath_simple] || 0
      bar_length = (value.to_f / max_xpath * 50).to_i
      f.puts "  #{adapter.to_s.capitalize.ljust(10)} #{"█" * bar_length} #{value.round(0)} ips"
    end
    f.puts "```"
    f.puts ""
  end

  def write_recommendations(f)
    f.puts "## Recommendations"
    f.puts ""

    # Find best performers
    best_parse = ADAPTERS.max_by { |a| @results[a][:parse_medium] || 0 }
    best_serialize = ADAPTERS.max_by { |a| @results[a][:serialize_medium] || 0 }
    best_xpath = ADAPTERS.max_by { |a| @results[a][:xpath_simple] || 0 }
    best_memory = ADAPTERS.min_by { |a| @results[a][:memory_medium] || Float::INFINITY }

    f.puts "### Best Performers"
    f.puts ""
    f.puts "- **Fastest Parser:** #{best_parse.to_s.capitalize} (#{@results[best_parse][:parse_medium]&.round(0)} ips)"
    f.puts "- **Fastest Serializer:** #{best_serialize.to_s.capitalize} (#{@results[best_serialize][:serialize_medium]&.round(0)} ips)"
    f.puts "- **Fastest XPath:** #{best_xpath.to_s.capitalize} (#{@results[best_xpath][:xpath_simple]&.round(0)} ips)"
    f.puts "- **Lowest Memory:** #{best_memory.to_s.capitalize} (#{@results[best_memory][:memory_medium]&.round(1)} MB per document)"
    f.puts ""

    f.puts "### Adapter Selection Guide"
    f.puts ""
    f.puts "**Choose Nokogiri when:**"
    f.puts "- You need industry-standard, battle-tested XML processing"
    f.puts "- Balanced performance across all operations is important"
    f.puts "- Full XPath and namespace support is required"
    f.puts "- You need the largest community and ecosystem"
    f.puts ""

    f.puts "**Choose Oga when:**"
    f.puts "- Pure Ruby implementation is required (JRuby, TruffleRuby)"
    f.puts "- You want good performance without C extensions"
    f.puts "- Cross-platform compatibility is critical"
    f.puts ""

    f.puts "**Choose REXML when:**"
    f.puts "- No external dependencies are allowed (stdlib only)"
    f.puts "- Maximum portability is needed"
    f.puts "- Performance is not the primary concern"
    f.puts "- You're working with small to medium documents"
    f.puts ""

    f.puts "**Choose LibXML when:**"
    f.puts "- You need an alternative to Nokogiri with similar features"
    f.puts "- Full namespace and XPath support is required"
    f.puts "- Good balance of speed and features is important"
    f.puts ""

    f.puts "**Choose Ox when:**"
    f.puts "- Maximum parsing and serialization speed is critical"
    f.puts "- Memory efficiency is paramount"
    f.puts "- XPath usage is minimal or you can work with basic queries"
    f.puts "- Document structures are relatively simple"
    f.puts ""
    f.puts "**CAUTION:** Ox's custom XPath engine supports common patterns but may not handle"
    f.puts "complex XPath expressions. Test thoroughly if advanced XPath is needed."
    f.puts ""
  end

  def write_environment_details(f)
    f.puts "## Test Environment"
    f.puts ""
    f.puts "- **Ruby Version:** #{RUBY_VERSION}"
    f.puts "- **Ruby Platform:** #{RUBY_PLATFORM}"
    f.puts "- **OS:** #{RbConfig::CONFIG["host_os"]}"
    f.puts "- **Architecture:** #{RbConfig::CONFIG["host_cpu"]}"
    f.puts "- **Moxml Version:** #{Moxml::VERSION}"
    f.puts "- **Benchmark Time:** #{@timestamp.strftime("%Y-%m-%d %H:%M:%S %Z")}"
    f.puts ""
    f.puts "### Gem Versions"
    f.puts ""
    ADAPTERS.each do |adapter|
      case adapter
      when :nokogiri
        require "nokogiri"
        f.puts "- Nokogiri: #{Nokogiri::VERSION}"
      when :oga
        require "oga"
        f.puts "- Oga: #{Oga::VERSION}"
      when :ox
        require "ox"
        f.puts "- Ox: #{Ox::VERSION}"
      when :libxml
        require "libxml"
        f.puts "- LibXML-Ruby: #{LibXML::XML::VERSION}"
      when :rexml
        f.puts "- REXML: (stdlib)"
      end
    rescue LoadError
      f.puts "- #{adapter.to_s.capitalize}: Not installed"
    end
    f.puts ""
  end

  def write_errors(f)
    f.puts "## Errors and Warnings"
    f.puts ""
    @errors.each do |adapter, errors|
      next if errors.empty?

      f.puts "### #{adapter.to_s.capitalize}"
      f.puts ""
      errors.each do |error|
        f.puts "- #{error}"
      end
      f.puts ""
    end
  end
end

# Run the benchmark report
if __FILE__ == $PROGRAM_NAME
  report = MoxmlBenchmarkReport.new
  report.run
end
