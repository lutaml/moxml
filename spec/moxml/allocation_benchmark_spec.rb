# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Moxml allocation benchmarks", :performance do
  # Helper: count object allocations during a block using GC stats
  def count_allocations
    GC.start
    GC.disable
    before = ObjectSpace.count_objects[:TOTAL]
    result = yield
    after = ObjectSpace.count_objects[:TOTAL]
    GC.enable
    after - before
  end

  # Generate a test XML document with N elements
  def generate_xml(element_count)
    inner = element_count.times.map { |i| "<elem#{i % 10}>text#{i}</elem#{i % 10}>" }.join
    "<root>#{inner}</root>"
  end

  shared_examples "reduced allocations" do |adapter_name|
    let(:ctx) { Moxml::Context.new(adapter_name) }

    it "parse allocates fewer objects than a 100-element baseline" do
      xml = generate_xml(100)
      allocs = count_allocations { ctx.parse(xml) }
      # Before lazy parse: ~18,000 allocations for 100 elements via DocumentBuilder
      # After lazy parse: should be dramatically less (document wrapper + root only)
      expect(allocs).to be < 5000,
        "Expected <5000 allocations for 100-element parse, got #{allocs}"
    end

    it "parse + root access is allocation-efficient" do
      xml = generate_xml(50)
      allocs = count_allocations do
        doc = ctx.parse(xml)
        doc.root.name
      end
      expect(allocs).to be < 2000,
        "Expected <2000 allocations for parse + root.name, got #{allocs}"
    end

    it "children access is cached (repeated calls don't increase allocations)" do
      xml = "<root><a/><b/><c/></root>"
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = count_allocations { root.children.to_a }
      allocs2 = count_allocations { root.children.to_a }

      # Second call should allocate fewer objects because children are cached
      expect(allocs2).to be <= allocs1,
        "Second children.to_a (#{allocs2}) should allocate <= first (#{allocs1})"
    end

    it "attributes access is cached" do
      xml = '<root a="1" b="2" c="3"><child d="4"/></root>'
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = count_allocations { root.attributes }
      allocs2 = count_allocations { root.attributes }

      expect(allocs2).to be <= allocs1,
        "Second attributes call (#{allocs2}) should allocate <= first (#{allocs1})"
    end

    it "namespaces access is cached" do
      xml = '<root xmlns:a="http://a.com" xmlns:b="http://b.com"><a:child/></root>'
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = count_allocations { root.namespaces }
      allocs2 = count_allocations { root.namespaces }

      expect(allocs2).to be <= allocs1,
        "Second namespaces call (#{allocs2}) should allocate <= first (#{allocs1})"
    end

    it "NodeSet iteration is cached (second iteration allocates less)" do
      xml = generate_xml(20)
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = count_allocations { root.children.each { |_c| } }
      allocs2 = count_allocations { root.children.each { |_c| } }

      expect(allocs2).to be <= allocs1,
        "Second NodeSet iteration (#{allocs2}) should allocate <= first (#{allocs1})"
    end
  end

  describe "Nokogiri adapter" do
    it_behaves_like "reduced allocations", :nokogiri
  end

  describe "Ox adapter" do
    it_behaves_like "reduced allocations", :ox
  end
end
