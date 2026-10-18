# frozen_string_literal: true

require "spec_helper"

# moxml#389: a comment token following ignored <html>/<body> start
# tags inserts at the current node (WHATWG 13.2.6.4.4 in-body
# comment insertion) — the ignored structural start tags do not
# change where comments land, and canon's strict-comments HTML
# comparisons ride the surface. Engine-side fix: leptris#1769
# (v1.9.370.1); the fragment path always wraps with <body>, so the
# in-body window gates apply.
RSpec.describe "parse_html_fragment comment preservation" do
  let(:ctx) { Moxml.new(:leptris) }

  before do
    unless Gem::Version.new(Leptris::VERSION) >= Gem::Version.new("1.9.370.1")
      skip "binding #{Leptris::VERSION} predates the in-body comment " \
           "fix (engine 1.9.370.1)"
    end
  end

  it "keeps a comment after ignored html/body start tags" do
    frag = ctx.parse_html_fragment(
      "<html><body><!-- c --><p>Test</p></body></html>",
    )
    kinds = frag.children.map { |c| c.class.name.split("::").last }
    expect(kinds).to include("Comment")
  end

  it "keeps the top-level comment shape unchanged" do
    frag = ctx.parse_html_fragment("<!-- c --><p>Test</p>")
    kinds = frag.children.map { |c| c.class.name.split("::").last }
    expect(kinds).to eq(%w[Comment Element])
  end

  it "round-trips the comment through serialization" do
    frag = ctx.parse_html_fragment(
      "<html><body><!-- c --><p>Test</p></body></html>",
    )
    expect(frag.to_html).to include("<!-- c -->")
  end
end
