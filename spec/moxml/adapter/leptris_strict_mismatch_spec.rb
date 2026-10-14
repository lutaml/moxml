# frozen_string_literal: true

require "spec_helper"

# Engine 1.9.355 (leptris#1700) names the tag mismatch in strict-parse
# failures — "expected </a>, got </b>" instead of the generic
# "malformed input". moxml passes the binding message through
# verbatim, so strict callers get the diagnostic for free; the spec
# pins it so a regression (or a re-genericization upstream) is caught.
RSpec.describe "leptris strict-parse mismatch diagnostic" do
  let(:ctx) { Moxml.new(:leptris) }

  context "when the engine names the mismatch (>= 1.9.355.0)" do
    before do
      unless Gem::Version.new(Leptris::VERSION) >= Gem::Version.new("1.9.355.0")
        skip "binding #{Leptris::VERSION} predates the mismatch diagnostic"
      end
    end

    it "names expected and got in the raised message" do
      expect do
        ctx.parse("<root><a></b></root>", strict: true)
      end.to raise_error(Moxml::ParseError) do |e|
        expect(e.message).to include("tag mismatch")
        expect(e.message).to include("</a>")
        expect(e.message).to include("</b>")
      end
    end

    it "reports the byte offset of the failure" do
      expect do
        ctx.parse("<root><a></b></root>", strict: true)
      end.to raise_error(Moxml::ParseError, /byte 13/)
    end
  end

  it "still raises Moxml::ParseError on strict parse failure" do
    expect do
      ctx.parse("<root><a></b></root>", strict: true)
    end.to raise_error(Moxml::ParseError)
  end
end
