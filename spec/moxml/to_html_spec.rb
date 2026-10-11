# frozen_string_literal: true

require "spec_helper"

# Document#to_html (issue #354): HTML-method serialization with the
# pretty-print knobs. The byte contract is per-engine pass-through —
# the leptris nested layout (engine leptris#1637) and Nokogiri's own
# serializer bytes — not cross-adapter byte equality.
RSpec.describe "Moxml::Document#to_html" do
  let(:src) do
    "<html><head><title>T</title></head><body><div id=\"a\"><p>x</p>" \
      "<span>y</span></div><script>if (a < b) { c(); }</script></body></html>"
  end

  describe "nokogiri" do
    let(:doc) { Moxml.new(:nokogiri).parse_html(src) }

    it "serializes the engine's HTML bytes by default" do
      expect(doc.to_html).to eq(Nokogiri::HTML(src).to_html)
    end

    it "threads indent through to the engine" do
      expect(doc.to_html(indent: 2))
        .to eq(Nokogiri::HTML(src).to_html(indent: 2))
    end

    it "threads the indent unit through to the engine" do
      expect(doc.to_html(indent: 1, indent_text: "\t"))
        .to eq(Nokogiri::HTML(src).to_html(indent: 1, indent_text: "\t"))
    end
  end

  describe "leptris" do
    let(:doc) { Moxml.new(:leptris).parse_html(src) }

    it "serializes single-line without kwargs" do
      expect(doc.to_html).to eq(doc.native.to_html)
      expect(doc.to_html).to start_with("<html>")
    end

    context "with the indent ride armed (binding >= 1.9.338.0)" do
      before do
        unless Moxml::Adapter::Leptris::HTML_SERIALIZE_INDENT
          skip "binding #{Leptris::VERSION} predates the #354 ride"
        end
      end

      it "nests block children with space leads" do
        expect(doc.to_html(indent: 2)).to eq(
          "<html>\n  " \
          "<head><title>T</title></head>\n  " \
          "<body>\n    " \
          "<div id=\"a\">\n      " \
          "<p>x</p>\n      " \
          "<span>y</span>\n    " \
          "</div>\n    " \
          "<script>if (a < b) { c(); }</script>\n  " \
          "</body>\n" \
          "</html>",
        )
      end

      it "nests with the indent_text unit" do
        expect(doc.to_html(indent: 1, indent_text: "\t")).to include(
          "<body>\n\t\t<div id=\"a\">\n\t\t\t<p>x</p>",
        )
      end
    end

    context "when the binding predates the ride" do
      before do
        if Moxml::Adapter::Leptris::HTML_SERIALIZE_INDENT
          skip "binding #{Leptris::VERSION} carries the ride"
        end
      end

      it "raises a named AdapterError instead of silently degrading" do
        expect { doc.to_html(indent: 2) }.to raise_error(Moxml::AdapterError, /indent/)
      end
    end
  end

  describe "adapters without an HTML serializer" do
    it "raise a named AdapterError" do
      doc = Moxml.new(:rexml).parse("<r><a>x</a></r>")
      expect { doc.to_html }
        .to raise_error(Moxml::AdapterError, /HTML serialization/)
    end
  end
end
