# frozen_string_literal: true

require "spec_helper"

# #364: DOCTYPE semantics converge across HTML-capable adapters —
# preserve-input-only (never synthesize: libxml2's HTML parser
# invents an HTML 4.0 doctype, which the nokogiri adapter drops),
# and the post-DOCTYPE separator is one newline (the leptris
# document-part walk used to stack the input's whitespace residue
# on top of the part newlines).
RSpec.describe "HTML DOCTYPE convergence (#364)" do
  let(:body) do
    "<html><head><title>t</title></head><body><p>x</p></body></html>"
  end

  %i[leptris nokogiri].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      it "never synthesizes a DOCTYPE the input lacked" do
        out = ctx.parse_html(body).to_s
        expect(out).not_to include("<!DOCTYPE")
        expect(out).to include("<html")
      end

      it "preserves the input DOCTYPE with a single separator" do
        out = ctx.parse_html("<!DOCTYPE html>\n#{body}").to_s
        expect(out).to start_with("<!DOCTYPE html>\n")
        expect(out.scan("<!DOCTYPE").size).to eq(1)
        expect(out).not_to include("\n\n\n")
      end

      it "preserves public/system identifiers verbatim" do
        src =
          '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" ' \
          '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">' \
          "\n#{body}"
        out = ctx.parse_html(src).to_s
        expect(out).to include("XHTML 1.0 Strict")
        expect(out.scan("<!DOCTYPE").size).to eq(1)
      end
    end
  end
end
