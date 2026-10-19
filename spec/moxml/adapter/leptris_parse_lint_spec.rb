# frozen_string_literal: true

require "spec_helper"

# Issue #404: Context#parse_html forwards collect_errors (and mode) to
# the leptris flags entry (leptris#1771's §13.2.5 parse-lint) — the
# recorded error tokens surface through parse_diagnostics. Face-probed:
# bindings predating the kwarg skip.
RSpec.describe "parse_html collect_errors forwarding" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:src) { %(<p class="x>unclosed</p><a href=><p>a<b</p>) }

  before do
    adapter = ctx.config.adapter
    supported = adapter.singleton_class.const_get(:COLLECT_ERRORS_NATIVE)
    skip "binding lacks the collect_errors kwarg (leptris#1771)" unless supported
  end

  it "surfaces parse-lint errors through parse_diagnostics" do
    doc = ctx.parse_html(src, collect_errors: true)
    diags = doc.parse_diagnostics
    expect(diags).not_to be_empty
    expect(diags.first).to have_key(:message)
  end

  it "keeps the default lane silent (no option, no diagnostics)" do
    doc = ctx.parse_html(src)
    expect(doc.parse_diagnostics).to be_empty
  end

  it "forwards through Context#parse_html options" do
    doc = ctx.parse_html(src, { collect_errors: true })
    expect(doc.parse_diagnostics).not_to be_empty
  end
end
