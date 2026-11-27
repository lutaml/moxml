# frozen_string_literal: true

require "spec_helper"

# lutaml/moxml#598: element blocks yield nil — nokogiri's Builder
# yields a scope bound to the created element, and the metanorma
# converter suite's 82+ call sites build through exactly that shape
# (`node.send(name, **attrs) { |n| n << val }`). The yield hands the
# Builder itself with its position on the new element (the face
# stack and the tree-path @current switch already place writes there
# for the zero-arg style), so `n <<` appends and `n.child` nests.
RSpec.describe "the yielded element scope (#598)" do
  describe "fragment mode (tree path)" do
    it "yields a scope whose << appends into the element" do
      out = Moxml.fragment(:leptris) do |xml|
        xml.title { |n| n << "T" }
      end.to_xml

      expect(out).to eq("<title>T</title>")
    end

    it "nests one-arg scopes" do
      out = Moxml.fragment(:leptris) do |xml|
        xml.p { |n| n.em { |e| e << "deep" } }
      end.to_xml

      expect(out).to eq("<p><em>deep</em></p>")
    end

    it "keeps the zero-arg style working" do
      out = Moxml.fragment(:leptris) do |xml|
        xml.p { text("plain") }
      end.to_xml

      expect(out).to eq("<p>plain</p>")
    end
  end

  describe "document mode (face path)" do
    it "yields a scope whose << appends into the element" do
      ctx = Moxml.new(:leptris)
      builder = Moxml::Builder.new(ctx)
      doc = builder.build do |xml|
        xml.root { |_n| xml.title { |n2| n2 << "T" } }
      end

      expect(doc.to_xml).to include("<title>T</title>")
    end

    it "nests one-arg scopes through the face" do
      ctx = Moxml.new(:leptris)
      builder = Moxml::Builder.new(ctx)
      doc = builder.build do |xml|
        xml.root { |_n| xml.p { |n2| n2.em { |e| e << "deep" } } }
      end

      # the face path pretty-prints - the structure is the contract
      expect(doc.to_xml).to include("<p>")
      expect(doc.to_xml).to include("<em>deep</em>")
    end
  end
end
