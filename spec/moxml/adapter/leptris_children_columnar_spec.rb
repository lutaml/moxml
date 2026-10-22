# frozen_string_literal: true
begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end
return unless Leptris::XML::Document.respond_to?(:create)
# The columnar children lane rides the binding's walk_columnar face
# (leptris-ruby#527/#532); older bindings keep the per-node children
# crossing, so the routing cannot be pinned there.
return unless defined?(Leptris::XML::Native) &&
              Leptris::XML::Native.respond_to?(:walk_columnar)
require "moxml/adapter/leptris"

RSpec.describe "Moxml::Adapter::Leptris columnar children (SOTA B2 walk row)" do
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

  # Counts real Native.walk_columnar C crossings inside the block —
  # no stubs, the actual boundary traffic the walk row pays.
  def with_crossing_count
    calls = 0
    tp = TracePoint.new(:c_call) do |t|
      calls += 1 if t.method_id == :walk_columnar
    end
    result = nil
    tp.enable { result = yield }
    [calls, result]
  end

  describe "the columnar gate" do
    it "face-probes walk_columnar on the binding" do
      expect(Moxml::Adapter::Leptris::COLUMNAR_WALK).to be(true)
      expect(Leptris::XML::Native.respond_to?(:walk_columnar)).to be(true)
    end
  end

  describe "plain children reads" do
    it "answer natives identical to the native children face" do
      got = Moxml::Adapter::Leptris.children(root_native)
      expected = Leptris::XML::NativeNode
                 .instance_method(:children).bind_call(root_native).to_a
      expect(got.size).to eq(expected.size)
      expect(got.map { |n| Moxml::Adapter::Leptris.node_name(n) })
             .to eq(expected.map(&:name))
      got.each_with_index do |native, i|
        # native-cache identity: cached handles ARE the children_read
        # wrappers, so the NodeSet contract holds.
        expect(native).to equal(expected[i])
      end
    end

    # Parsed-document wrappers mint with Identity::ChildReads above
    # Moxml::Node, so consumer iteration on those wrappers dispatches
    # to the binding's C read layer. The children FACE is pinned by
    # driving it for every node of the cold subtree: one walk_columnar
    # crossing primes the whole map, every deeper face read hits it.
    it "pay ONE columnar crossing for a whole cold subtree" do
      calls, = with_crossing_count do
        walk_face = lambda do |native|
          Moxml::Adapter::Leptris.children(native).each do |child|
            walk_face.call(child)
          end
        end
        walk_face.call(root_native)
      end
      expect(calls).to eq(1)
    end

    it "serve repeat face reads from the primed map without a crossing" do
      calls, first = with_crossing_count do
        Moxml::Adapter::Leptris.children(root_native)
      end
      expect(calls).to eq(1)
      first_names = first.map { |n| Moxml::Adapter::Leptris.node_name(n) }
      calls2, second = with_crossing_count do
        Moxml::Adapter::Leptris.children(root_native)
      end
      expect(calls2).to eq(0)
      expect(second.map { |n| Moxml::Adapter::Leptris.node_name(n) })
             .to eq(first_names)
    end
  end

  describe "mutation invalidation" do
    # Read back through the adapter face: the map must never serve a
    # list a mutation has invalidated.
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
