# frozen_string_literal: true

require "spec_helper"

# moxml#315: unions are N-ARY in the parser (a|b|c parses to one
# union node); the compiler's two-children destructure silently
# dropped every branch after the second. The reserved xmlns prefix
# hid the drop for namespaced consumers because those queries rode
# the native seam; when they fell back to the Ruby engine (or on
# adapters whose engine IS this one, e.g. ox), branches vanished.
RSpec.describe "XPath union compilation" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) { ctx.parse('<r xmlns="urn:x"><a>1</a><b>2</b><c>3</c></r>') }

  it "keeps every branch of a flat n-ary union (moxml#315)" do
    r = doc.at_xpath("/xmlns:r", { "xmlns" => "urn:x" })
    names = r.xpath("./xmlns:a|./xmlns:b|./xmlns:c", { "xmlns" => "urn:x" })
      .map(&:text)
    expect(names).to eq(%w[1 2 3])
  end

  it "keeps branches under the reserved xmlns prefix through the engine" do
    r = doc.at_xpath("/xmlns:r", { "xmlns" => "urn:x" })
    ast = Moxml::XPath::Parser.parse("./xmlns:a|./xmlns:b|./xmlns:c")
    proc_c = Moxml::XPath::Compiler.compile_with_cache(ast, namespaces: { "xmlns" => "urn:x" })
    expect(proc_c.call(r).to_a.map(&:text)).to eq(%w[1 2 3])
  end

  it "keeps parenthesized nested unions" do
    r = doc.at_xpath("/xmlns:r", { "xmlns" => "urn:x" })
    ast = Moxml::XPath::Parser.parse("(./xmlns:a|./xmlns:b)|./xmlns:c")
    proc_c = Moxml::XPath::Compiler.compile_with_cache(ast, namespaces: { "xmlns" => "urn:x" })
    expect(proc_c.call(r).to_a.map(&:text)).to eq(%w[1 2 3])
  end

  it "unions still work on adapters whose engine is the Ruby engine" do
    ctx_ox = Moxml.new(:ox)
    doc_ox = ctx_ox.parse("<r><a>1</a><b>2</b><c>3</c></r>")
    r = doc_ox.root
    expect(r.xpath("./a|./b|./c").map(&:text)).to eq(%w[1 2 3])
  end
end
