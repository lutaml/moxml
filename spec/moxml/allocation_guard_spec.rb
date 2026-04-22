# frozen_string_literal: true

require "spec_helper"
require "support/allocation_helper"

# Allocation guard specs — these run in CI by default (no :performance tag).
#
# These specs enforce allocation budgets per adapter per operation.
# If an adapter exceeds its threshold, the spec fails with a diagnostic
# message showing the actual vs expected allocation count.
#
# Thresholds are in AllocationHelper::THRESHOLDS and should be tightened
# as optimizations are confirmed.
RSpec.describe "Allocation guards", order: :defined do
  def threshold_for(adapter_name, operation)
    AllocationHelper.threshold(adapter_name, operation)
  end

  def guard_allocations(adapter_name, operation, &block)
    allocs = AllocationHelper.count_allocations(&block)
    limit = threshold_for(adapter_name, operation)

    if allocs > limit
      # Generate StackProf diagnostic on failure
      profile = AllocationHelper.profile_allocations(&block)
      raise(<<~MSG)
        #{adapter_name}/#{operation}: #{allocs} allocations exceeds limit of #{limit}

        #{profile}
      MSG
    end
    allocs
  end

  shared_examples "allocation guard" do |adapter_name|
    let(:ctx) { Moxml::Context.new(adapter_name) }

    # ----------------------------------------------------------------
    # Parse allocation guard
    # ----------------------------------------------------------------
    describe "parse allocations" do
      it "parses 100-element document within allocation budget" do
        xml = generate_xml(100)
        allocs = guard_allocations(adapter_name, :parse_100) { ctx.parse(xml) }
        expect(allocs).to be <= threshold_for(adapter_name, :parse_100)
      end

      it "parses 50-element document within allocation budget" do
        xml = generate_xml(50)
        allocs = guard_allocations(adapter_name, :parse_50) { ctx.parse(xml) }
        expect(allocs).to be <= threshold_for(adapter_name, :parse_50)
      end

      it "parse + root.name is allocation-efficient" do
        xml = generate_xml(100)
        allocs = guard_allocations(adapter_name, :parse_and_root) do
          doc = ctx.parse(xml)
          doc.root.name
        end
        expect(allocs).to be <= threshold_for(adapter_name, :parse_and_root)
      end
    end

    # ----------------------------------------------------------------
    # Cache hit guards — second access should allocate near-zero objects
    # ----------------------------------------------------------------
    describe "cache hit guards" do
      let(:simple_xml) { "<root><a/><b/><c/></root>" }
      let(:attr_xml) { '<root x="1" y="2" z="3"><child k="4"/></root>' }

      it "children access is cached after first call" do
        doc = ctx.parse(simple_xml)
        root = doc.root
        # Warm the cache
        root.children.to_a

        allocs = AllocationHelper.count_allocations { root.children.to_a }
        expect(allocs).to be <= threshold_for(adapter_name, :cached_children_access),
                          "Second children access (#{allocs}) should allocate <= #{threshold_for(
                            adapter_name, :cached_children_access
                          )}"
      end

      it "attributes access is cached after first call" do
        doc = ctx.parse(attr_xml)
        root = doc.root
        # Warm the cache
        root.attributes

        allocs = AllocationHelper.count_allocations { root.attributes }
        expect(allocs).to be <= threshold_for(adapter_name, :cached_attributes_access),
                          "Second attributes access (#{allocs}) should allocate <= #{threshold_for(
                            adapter_name, :cached_attributes_access
                          )}"
      end

      it "NodeSet iteration is cached on second pass" do
        xml = generate_xml(20)
        doc = ctx.parse(xml)
        root = doc.root
        # Warm the cache
        root.children.each { |_| nil }

        allocs = AllocationHelper.count_allocations do
          root.children.each do |_|
            nil
          end
        end
        expect(allocs).to be <= threshold_for(adapter_name, :cached_iteration),
                          "Second NodeSet iteration (#{allocs}) should allocate <= #{threshold_for(
                            adapter_name, :cached_iteration
                          )}"
      end
    end

    # ----------------------------------------------------------------
    # Round-trip allocation guard
    # ----------------------------------------------------------------
    describe "round-trip allocations" do
      it "parse → serialize → parse stays within budget" do
        xml = generate_xml(50)
        allocs = guard_allocations(adapter_name, :round_trip) do
          doc = ctx.parse(xml)
          serialized = doc.to_xml
          ctx.parse(serialized)
        end
        expect(allocs).to be <= threshold_for(adapter_name, :round_trip)
      end
    end

    # ----------------------------------------------------------------
    # Scalability guard — allocations grow linearly, not quadratically
    # ----------------------------------------------------------------
    describe "scalability" do
      it "allocation growth is linear with document size" do
        xml_100 = generate_xml(100)
        xml_200 = generate_xml(200)

        allocs_100 = AllocationHelper.count_allocations { ctx.parse(xml_100) }
        allocs_200 = AllocationHelper.count_allocations { ctx.parse(xml_200) }

        ratio = allocs_200.to_f / allocs_100
        max_ratio = threshold_for(adapter_name, :scalability_ratio)

        expect(ratio).to be <= max_ratio,
                         "200-element parse (#{allocs_200}) vs 100-element (#{allocs_100}) = #{ratio.round(2)}x, " \
                         "expected <= #{max_ratio}x (linear growth)"
      end
    end

    # ----------------------------------------------------------------
    # Cache invalidation guards — mutation breaks cache
    # ----------------------------------------------------------------
    describe "cache invalidation" do
      it "adding a child invalidates children cache" do
        xml = "<root><a/></root>"
        doc = ctx.parse(xml)
        root = doc.root
        children_before = root.children

        new_elem = ctx.parse("<b/>").root
        root.add_child(new_elem)

        children_after = root.children
        expect(children_before).not_to equal(children_after),
                                       "Children cache should be invalidated after add_child"
        expect(children_after.size).to eq(2)
      end

      it "setting text invalidates children cache" do
        xml = "<root><a/></root>"
        doc = ctx.parse(xml)
        root = doc.root
        children_before = root.children

        root.text = "replaced"

        children_after = root.children
        expect(children_before).not_to equal(children_after),
                                       "Children cache should be invalidated after text="
      end

      it "setting attribute invalidates attributes cache" do
        xml = '<root a="1"/>'
        doc = ctx.parse(xml)
        root = doc.root
        attrs_before = root.attributes

        root["b"] = "2"

        attrs_after = root.attributes
        expect(attrs_before).not_to equal(attrs_after),
                                    "Attributes cache should be invalidated after []="
        expect(attrs_after.size).to eq(2)
      end

      it "removing attribute invalidates attributes cache" do
        xml = '<root a="1" b="2"/>'
        doc = ctx.parse(xml)
        root = doc.root
        attrs_before = root.attributes

        root.remove_attribute("a")

        attrs_after = root.attributes
        expect(attrs_before).not_to equal(attrs_after),
                                    "Attributes cache should be invalidated after remove_attribute"
        expect(attrs_after.size).to eq(1)
      end

      it "removing a child invalidates parent's children cache" do
        xml = "<root><a/><b/></root>"
        doc = ctx.parse(xml)
        root = doc.root
        children_before = root.children
        child_a = root.children.first

        child_a.remove

        children_after = root.children
        expect(children_before).not_to equal(children_after),
                                       "Parent's children cache should be invalidated after child.remove"
        expect(children_after.size).to eq(1)
      end
    end

    # ----------------------------------------------------------------
    # NodeSet wrap cache guards
    # ----------------------------------------------------------------
    describe "NodeSet wrap cache" do
      it "returns the same wrapper for same index" do
        doc = ctx.parse("<root><a/><b/><c/></root>")
        children = doc.root.children

        first_access = children[0]
        second_access = children[0]
        expect(first_access).to equal(second_access),
                                "Same index should return identical wrapper object"
      end

      it "returns the same wrapper from each as from []" do
        doc = ctx.parse("<root><a/><b/><c/></root>")
        children = doc.root.children

        from_each = nil
        children.each { |c| from_each = c if c.name == "b" }
        from_index = children[1]

        expect(from_each).to equal(from_index),
                             "Node from #each should be identical to same index from #[]"
      end

      it "preserves cache across multiple iterations" do
        doc = ctx.parse("<root><a/><b/><c/></root>")
        children = doc.root.children

        pass1 = children.map(&:name)
        pass2 = children.map(&:name)

        expect(pass1).to eq(pass2)
        # Also verify object identity between passes
        pass1_nodes = children.to_a
        pass2_nodes = children.to_a
        pass1_nodes.each_with_index do |node, i|
          expect(node).to equal(pass2_nodes[i]),
                          "Node #{i} should be identical across iterations"
        end
      end
    end
  end

  # Run guards for each adapter
  AllocationHelper::GUARDED_ADAPTERS.each do |adapter_name|
    describe "#{adapter_name} adapter" do
      before(:all) do
        skip("#{adapter_name} adapter not available") unless AllocationHelper.adapter_available?(adapter_name)
      end

      it_behaves_like "allocation guard", adapter_name
    end
  end
end
