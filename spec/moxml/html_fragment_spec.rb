# frozen_string_literal: true

require "spec_helper"

# Context#parse_html_fragment (#353): WHATWG fragment semantics on
# the moxml surface — head-swept elements stay at fragment top
# level, table-structure tags follow the in-body rules, whitespace
# is preserved. The leptris lane composes over the binding's
# fragment face (leptris-ruby#422); nokogiri maps to
# Nokogiri::HTML5.fragment.
RSpec.describe "Context#parse_html_fragment" do
  describe "nokogiri" do
    let(:ctx) { Moxml.new(:nokogiri) }

    it "keeps head-swept elements at fragment top level" do
      frag = ctx.parse_html_fragment("<title>T</title><p>x</p>")
      expect(frag.children.map(&:name)).to eq(%w[title p])
      expect(frag.children.first).to be_element
    end

    it "drops table-structure elements, keeping their text" do
      frag = ctx.parse_html_fragment("<td>cell</td>")
      expect(frag.children.map(&:name)).to eq(["text"])
      expect(frag.children.first.text).to eq("cell")
    end

    it "preserves whitespace-only text" do
      frag = ctx.parse_html_fragment("  <p>lead ws</p>  ")
      expect(frag.children.map(&:name).first).to eq("text")
    end

    it "is enumerable and serializes as children joined" do
      frag = ctx.parse_html_fragment("<p>a</p>tail")
      expect(frag.size).to eq(2)
      expect(frag.to_html).to eq("<p>a</p>tail")
      expect(frag).not_to be_empty
      expect(ctx.parse_html_fragment("")).to be_empty
    end

    it "wraps children with the context" do
      frag = ctx.parse_html_fragment("<p>x</p>")
      expect(frag.children.first.context).to eq(ctx)
    end
  end

  describe "leptris" do
    let(:ctx) { Moxml.new(:leptris) }

    before do
      unless Moxml::Adapter::Leptris::HTML_FRAGMENT
        skip "binding #{Leptris::VERSION} predates the #353 fragment face"
      end
    end

    it "keeps head-swept elements at fragment top level" do
      frag = ctx.parse_html_fragment("<title>T</title><p>x</p>")
      expect(frag.children.map(&:name)).to eq(%w[title p])
    end

    it "parses inside a table context" do
      frag = ctx.parse_html_fragment("<b>x</b>", context_tag: :td)
      expect(frag.children.map(&:name)).to eq(%w[b])
    end

    it "raises a named error for unknown context tags" do
      expect { ctx.parse_html_fragment("<p/>", context_tag: :nope) }
        .to raise_error(Moxml::AdapterError, /table context/)
    end

    it "drops table-structure elements, keeping their text" do
      frag = ctx.parse_html_fragment("<td>cell</td>")
      expect(frag.children.map(&:name)).to eq(["text"])
      expect(frag.children.first.text).to eq("cell")
    end

    it "serializes as children joined" do
      expect(ctx.parse_html_fragment("<p>a</p>tail").to_html).to eq("<p>a</p>tail")
    end
  end

  describe "adapters without fragment support" do
    it "raise a named AdapterError" do
      expect { Moxml.new(:rexml).parse_html_fragment("<p>x</p>") }
        .to raise_error(Moxml::AdapterError, /HTML fragment parsing/)
    end
  end
end
