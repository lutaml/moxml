# frozen_string_literal: true

require "spec_helper"
require "support/allocation_helper"

# Detailed allocation benchmarks — only run with RUN_PERFORMANCE=1.
# These measure exact allocation counts and compare across adapters.
RSpec.describe "Moxml allocation benchmarks", :performance do
  shared_examples "reduced allocations" do |adapter_name|
    let(:ctx) { Moxml::Context.new(adapter_name) }

    it "parse allocates fewer objects than a 100-element baseline" do
      xml = generate_xml(100)
      allocs = AllocationHelper.count_allocations { ctx.parse(xml) }
      # Before lazy parse: ~18,000 allocations for 100 elements via DocumentBuilder
      # After lazy parse: should be dramatically less (document wrapper + root only)
      expect(allocs).to be < 5000,
        "Expected <5000 allocations for 100-element parse, got #{allocs}"
    end

    it "parse + root access is allocation-efficient" do
      xml = generate_xml(50)
      allocs = AllocationHelper.count_allocations do
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

      allocs1 = AllocationHelper.count_allocations { root.children.to_a }
      allocs2 = AllocationHelper.count_allocations { root.children.to_a }

      # Second call should allocate fewer objects because children are cached
      expect(allocs2).to be <= allocs1,
        "Second children.to_a (#{allocs2}) should allocate <= first (#{allocs1})"
    end

    it "attributes access is cached" do
      xml = '<root a="1" b="2" c="3"><child d="4"/></root>'
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = AllocationHelper.count_allocations { root.attributes }
      allocs2 = AllocationHelper.count_allocations { root.attributes }

      expect(allocs2).to be <= allocs1,
        "Second attributes call (#{allocs2}) should allocate <= first (#{allocs1})"
    end

    it "namespaces access is cached" do
      xml = '<root xmlns:a="http://a.com" xmlns:b="http://b.com"><a:child/></root>'
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = AllocationHelper.count_allocations { root.namespaces }
      allocs2 = AllocationHelper.count_allocations { root.namespaces }

      expect(allocs2).to be <= allocs1,
        "Second namespaces call (#{allocs2}) should allocate <= first (#{allocs1})"
    end

    it "NodeSet iteration is cached (second iteration allocates less)" do
      xml = generate_xml(20)
      doc = ctx.parse(xml)
      root = doc.root

      allocs1 = AllocationHelper.count_allocations { root.children.each { |_c| } }
      allocs2 = AllocationHelper.count_allocations { root.children.each { |_c| } }

      expect(allocs2).to be <= allocs1,
        "Second NodeSet iteration (#{allocs2}) should allocate <= first (#{allocs1})"
    end
  end

  AllocationHelper::GUARDED_ADAPTERS.each do |adapter_name|
    describe "#{adapter_name} adapter" do
      before(:all) do
        skip("#{adapter_name} adapter not available") unless AllocationHelper.adapter_available?(adapter_name)
      end

      it_behaves_like "reduced allocations", adapter_name
    end
  end
end
