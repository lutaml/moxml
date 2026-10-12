# frozen_string_literal: true

require "spec_helper"

# #369: non-strict parses RECOVER on engines carrying the mode
# (leptris 1.9.344+, leptris#1660) — the best-effort tree survives
# recoverable structural errors (libxml2 XML_PARSE_RECOVER
# semantics) instead of the rescue-to-empty fallback. Strict
# callers never recover: malformed input raises.
RSpec.describe "recover mode (#369)" do
  let(:ctx) { Moxml.new(:leptris) }

  describe "engines with the recover mode" do
    before do
      unless Moxml::Adapter::Leptris::RECOVER_MODE
        skip "binding #{Leptris::VERSION} predates the recover mode"
      end
    end

    it "recovers a mismatched closer into a tree" do
      doc = ctx.parse("<root><a>x</b></root>", strict: false)
      expect(doc.root).not_to be_nil
      expect(doc.to_xml).to include("<a>x</a>")
    end

    it "closes unclosed elements at EOF" do
      doc = ctx.parse("<root><a>x</root>", strict: false)
      expect(doc.root).not_to be_nil
      expect(doc.to_xml).to include("<a>x</a>")
    end

    it "keeps strict parsing raising" do
      expect { ctx.parse("<root><a>x</b></root>", strict: true) }
        .to raise_error(Moxml::ParseError)
    end

    it "raises by default (Context strict_parsing defaults true)" do
      expect { ctx.parse("<root><a>x</b></root>") }
        .to raise_error(Moxml::ParseError)
    end

    it "the recovered tree carries no parse errors (diagnostics ride #1200)" do
      doc = ctx.parse("<root><a>x</b></root>", strict: false)
      expect(doc.parse_errors).to eq([])
    end
  end

  describe "engines below the recover floor" do
    before do
      if Moxml::Adapter::Leptris::RECOVER_MODE
        skip "binding #{Leptris::VERSION} carries the recover mode"
      end
    end

    it "keeps the empty-document fallback with diagnostics" do
      doc = ctx.parse("<root><a>x</b></root>", strict: false)
      expect(doc.root).to be_nil
      expect(doc.parse_errors).not_to be_empty
    end
  end
end
