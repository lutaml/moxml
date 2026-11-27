# frozen_string_literal: true

require "spec_helper"

# Fragment building (#584): sibling roots accumulate without a wrapper
# element; the markup-accumulating face flushes into an element sink so
# multi-root payloads cross natively in one shot.
RSpec.describe Moxml::Fragment do
  let(:context) { Moxml.new }

  describe "Context#build_fragment" do
    it "builds sibling roots without a wrapper element in the output" do
      fragment = context.build_fragment do
        p_ "first"
        b_ "bold"
        i_ do
          u_ "deep"
        end
      end

      expect(fragment).to be_a(described_class)
      expect(fragment.to_xml(indent: 0))
        .to eq("<p>first</p><b>bold</b><i><u>deep</u></i>")
    end

    it "walks children as wrapped nodes" do
      fragment = context.build_fragment do
        p_ "one"
        p_ "two"
      end

      expect(fragment.children.size).to eq(2)
      expect(fragment.children.map(&:name)).to eq(%w[p p])
    end

    it "accepts text, comments and processing instructions as children" do
      fragment = context.build_fragment do
        text "bare text"
        comment "a note"
      end

      expect(fragment.to_xml(indent: 0))
        .to eq("bare text<!--a note-->")
    end

    it "honors serialization options on every child" do
      fragment = context.build_fragment do
        p_ "x"
        br_
      end

      expect(fragment.to_xml(indent: 0)).to eq("<p>x</p><br/>")
    end

    it "keeps face-built and tree-built children in one storage" do
      fragment = context.build_fragment do
        p_ "from the face"
      end
      # After the face flushed (its builder retired), tree ops append
      # into the same storage.
      node = fragment.create_element("q")
      node.add_child(fragment.create_text("from the tree"))
      fragment.add_child(node)

      expect(fragment.children.size).to eq(2)
      expect(fragment.to_xml(indent: 0)).to eq("<p>from the face</p><q>from the tree</q>")
    end

    it "resolves element-scoped namespaces (deferred tree-ops retarget)" do
      fragment = context.build_fragment do
        math_("xmlns:mml" => "http://www.w3.org/1998/Math/MathML") do
          self["mml"].mi "x"
        end
      end

      output = fragment.to_xml(indent: 0)
      expect(output).to include("xmlns:mml")
      expect(output).to include("<mml:mi>x</mml:mi>")
    end

    it "propagates strict mode" do
      expect do
        context.build_fragment(strict: true) do
          nonsense_
        end
      end.to raise_error(NoMethodError, /fragment|moxml#584|strict/i)
    end

    it "rejects XML declarations and doctypes" do
      expect do
        context.build_fragment do
          declaration version: "1.0"
        end
      end.to raise_error(ArgumentError, /declaration/)

      expect do
        context.build_fragment do
          doctype "svg"
        end
      end.to raise_error(ArgumentError, /doctype/)
    end

    it "renders an empty fragment as an empty string" do
      fragment = context.build_fragment do
        # nothing
      end
      expect(fragment.to_xml(indent: 0)).to eq("")
    end
  end
end
