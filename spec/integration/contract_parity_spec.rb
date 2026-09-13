# frozen_string_literal: true

# Cross-adapter contract parity (issue #198): every bundled adapter
# runs the same behavioral battery, so parity is CI-enforced rather
# than discovered by consumers.
%w[nokogiri leptris ox oga rexml].each do |adapter_name|
  begin
    next unless Moxml::Adapter.load_available?(adapter_name.to_sym)
  rescue StandardError
    false
  end

  RSpec.describe "Contract parity: #{adapter_name}", :adapter do
    around do |example|
      Moxml.with_config(adapter_name.to_sym, true, "UTF-8") do
        example.run
      end
    end

    let(:ctx) { Moxml.new(adapter_name.to_sym) }

    describe "fragment parsing (issue #188)" do
      it "returns the fragment's top-level nodes uniformly" do
        nodes = ctx.parse_fragment(%(<a x="1">t1</a><b/>tail))
        expect(nodes.map(&:class)).to eq(
          [Moxml::Element, Moxml::Element, Moxml::Text],
        )
        expect(nodes[0]["x"]).to eq("1")
        expect(nodes[0].text).to eq("t1")
        expect(nodes[2].content).to eq("tail")
      end

      it "round-trips entities inside fragments" do
        nodes = ctx.parse_fragment(%(<p>caf&eacute; &amp; more</p>))
        # The moxml XML contract preserves entity REFERENCES in
        # text reads (the entity-preservation design) — uniform
        # across adapters, fragments included.
        expect(nodes.first.content).to include("&eacute;")
        expect(nodes.first.to_xml).to include("&amp;")
      end

      it "returns [] for an empty fragment" do
        expect(ctx.parse_fragment("")).to eq([])
      end
    end

    describe "nil namespace clearing (issue #164 contract)" do
      it "accepts namespace = nil without raising" do
        doc = ctx.parse(%(<r xmlns="urn:d"><c>t</c></r>))
        child = doc.root.children.first
        expect { child.namespace = nil }.not_to raise_error
      end
    end

    describe "namespace adoption on append" do
      it "keeps a subtree's own declarations when appended" do
        doc = ctx.parse(%(<root/>))
        nodes = ctx.parse_fragment(%(<p:s xmlns:p="urn:p">x</p:s>))
        doc.root.add_child(nodes.first)
        out = doc.to_xml
        expect(out).to include("urn:p")
        expect(out).to include("x")
      end
    end

    describe "namespaces contract (issue #198 comment)" do
      it "returns the in-scope map including ancestor declarations" do
        doc = ctx.parse(%(<root xmlns:p="urn:p" xmlns="urn:d"><p:c plain="1"/></root>))
        child = doc.root.children.first
        map = child.namespaces.map { |n| [n.prefix, n.uri.to_s] }
        expect(map).to contain_exactly(["p", "urn:p"], [nil, "urn:d"])
      end

      it "namespace_definitions stays the element's own declarations" do
        doc = ctx.parse(%(<root xmlns:p="urn:p"><p:c/></root>))
        child = doc.root.children.first
        expect(child.namespace_definitions).to be_empty
        expect(doc.root.namespace_definitions.map(&:prefix)).to eq(["p"])
      end
    end

    describe "attribute channel semantics" do
      it "reads and writes bare and prefixed attributes" do
        doc = ctx.parse(%(<r xmlns:p="urn:p"><e a="1" p:b="2"/></r>))
        e = doc.at_xpath("//e")
        expect(e["a"]).to eq("1")
        expect(e["p:b"]).to eq("2")
        e["a"] = "changed"
        expect(e["a"]).to eq("changed")
        expect(e["p:b"]).to eq("2")
      end
    end
  end
end
