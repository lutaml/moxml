# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end
return unless Leptris::XML::Document.respond_to?(:create)
# The address-native lane rides the binding's shadow faces
# (children_addrs / walk_addresses, leptris-ruby#587/#589/#591);
# older bindings keep the columnar per-subtree crossing, so the
# routing cannot be pinned there.
return unless defined?(Leptris::XML::Native) &&
  Leptris::XML::Native.respond_to?(:children_addrs)

require "moxml/adapter/leptris"

RSpec.describe "Moxml::Adapter::Leptris address-native children (shadow lane)" do
  around do |example|
    Moxml.with_config(:leptris, true, "UTF-8") do
      example.run
    end
  end

  let(:xml) do
    <<~XML
      <?xml version="1.0"?><r><a x="1">t</a><b/><c><d/></c><tail>z</tail></r>
    XML
  end

  let(:doc) { Moxml.parse(xml) }
  let(:root) { doc.root }
  let(:root_native) { root.native }

  # Counts real Native.children_addrs C crossings inside the block —
  # no stubs, the actual boundary traffic the address lane pays.
  def with_crossing_count(method_id = :children_addrs)
    calls = 0
    tp = TracePoint.new(:c_call) do |t|
      calls += 1 if t.method_id == method_id
    end
    result = nil
    tp.enable { result = yield }
    [calls, result]
  end

  describe "the address gate" do
    it "face-probes the shadow faces on the binding" do
      expect(Moxml::Adapter::Leptris::ADDRESS_NATIVE).to be(true)
      expect(Leptris::XML::Native.respond_to?(:children_addrs)).to be(true)
    end
  end

  describe "plain children reads" do
    it "answer address tokens matching the native children face" do
      got = Moxml::Adapter::Leptris.children(root_native)
      expected = Leptris::XML::NativeNode
        .instance_method(:children).bind_call(root_native).to_a
      expect(got).to all(be_a(Moxml::Adapter::Leptris::AddressNode))
      expect(got.size).to eq(expected.size)
      expect(got.map { |n| Moxml::Adapter::Leptris.node_name(n) })
        .to eq(expected.map(&:name))
      got.each_with_index do |token, i|
        # Address equality: the token stands for the same C node.
        expect(token.address).to eq(expected[i].address)
        expect(Moxml::Adapter::Leptris.node_type(token))
          .to eq(Moxml::Adapter::Leptris.node_type(expected[i]))
      end
    end

    it "hand back the SAME token per address across traversals" do
      first = Moxml::Adapter::Leptris.children(root_native)
      second = Moxml::Adapter::Leptris.children(root_native)
      expect(second).to eq(first)
      expect(second.first).to equal(first.first)
    end

    # Parsed-document wrappers mint with Identity::ChildReads above
    # Moxml::Node, so consumer iteration on those wrappers dispatches
    # to the binding's C read layer. The address face pays one
    # children_addrs crossing per element receiver — the token mint
    # replaces the TypedData wrap + identity-cache write the columnar
    # lane pays per node in C.
    it "pay one crossing per element receiver, none on repeat reads" do
      calls, = with_crossing_count do
        walk_face = lambda do |token|
          Moxml::Adapter::Leptris.children(token).each do |child|
            walk_face.call(child)
          end
        end
        walk_face.call(root_native)
      end
      # The subtree has 6 elements (r, a, b, c, d, tail): one crossing
      # each, no walk_columnar at all.
      expect(calls).to eq(6)
      calls2, = with_crossing_count do
        Moxml::Adapter::Leptris.children(root_native)
      end
      expect(calls2).to eq(1)
    end

    it "serve element reads through the address-keyed faces" do
      target = Moxml::Adapter::Leptris.children(root_native)
        .find { |t| Moxml::Adapter::Leptris.node_name(t) == "a" }
      expect(Moxml::Adapter::Leptris.bare_attr_value(target, "x")).to eq("1")
      expect(Moxml::Adapter::Leptris.text_content(target)).to eq("t")
      expect(Moxml::Adapter::Leptris.attributes(target).map(&:value))
        .to eq(["1"])
    end

    it "keep the document assembly path on document receivers" do
      calls, doc_children = with_crossing_count do
        Moxml::Adapter::Leptris.children(doc.native)
      end
      # No token crossings: the document's child list rides the
      # assembly path (declaration/doctype kinds are outside the
      # address lane's WS enum).
      expect(calls).to eq(0)
      expect(doc_children.map do |n|
        Moxml::Adapter::Leptris.node_name(n)
      end).to include("r")
    end
  end

  describe "mutation invalidation" do
    # Read back through the adapter face: the token map must never
    # serve a list a mutation has invalidated.
    def face_children_names
      Moxml::Adapter::Leptris.children(root_native)
        .map { |n| Moxml::Adapter::Leptris.node_name(n) }
    end

    it "sees children added after the map was primed" do
      face_children_names # prime the map
      root.add_child(doc.create_element("late"))
      expect(face_children_names).to include("late")
    end

    it "sees children removed after the map was primed" do
      face_children_names # prime the map
      root.children.to_a.first.remove
      expect(face_children_names).not_to include("a")
    end

    it "sees sibling insertions after the map was primed" do
      face_children_names # prime the map
      anchor = root.children.to_a.first
      anchor.add_previous_sibling(doc.create_element("before2"))
      expect(face_children_names).to include("before2")
    end

    it "sees replace after the map was primed" do
      face_children_names # prime the map
      victim = root.children.to_a.find { |n| n.name == "b" }
      victim.replace(doc.create_element("swapped"))
      expect(face_children_names).to include("swapped")
      expect(face_children_names).not_to include("b")
    end

    it "sees content rewrites after the map was primed" do
      face_children_names # prime the map
      target = root.children.to_a.find { |n| n.name == "a" }
      target.content = "rewritten"
      names = face_children_names
      expect(names).to include("a")
      expect(root.children.to_a.find { |n| n.name == "a" }.text)
        .to eq("rewritten")
    end
  end
end
