# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Materializer do
  let(:xml) do
    <<~XML
      <catalog xmlns="urn:c" xmlns:p="urn:p">
        <book id="b1" p:lang="en"><title>T</title><!--n--><?pi x?><![CDATA[raw]]></book>
      </catalog>
    XML
  end

  def records_for(adapter)
    Moxml.new(adapter).materialize(xml).to_a
  end

  it "emits one record per node in post-order with depth, names, and attributes" do
    records = records_for(:leptris)

    expect(records.map { |r| [r[:kind], r[:depth]] }).to eq(
      [
        # post-order: whitespace before <book>, then the book subtree,
        # then the trailing whitespace, then the catalog itself
        [:text, 1],
        [:text, 3], [:element, 2], [:comment, 2],
        [:processing_instruction, 2], [:cdata, 2],
        [:element, 1],
        [:text, 1],
        [:element, 0]
      ],
    )

    book = records.find { |r| r[:qname] == "book" }
    expect(book[:attributes]).to include(["id", "b1", nil, nil], ["lang", "en", "urn:p", "p"])
    expect(book[:namespace_uri]).to eq("urn:c")
    expect(book[:text]).to be_nil

    catalog = records.last
    expect(catalog[:namespaces]).to eq([[nil, "urn:c"], ["p", "urn:p"]])
    expect(book[:namespaces]).to eq([])

    title_text = records.find { |r| r[:kind] == :text && r[:text] == "T" }
    expect(title_text[:attributes]).to eq([])
  end

  it "uses the same record stream on the bulk path and the generic walk" do
    skip "leptris not installed" unless Moxml::Adapter.available?(:leptris)

    expect(records_for(:leptris)).to eq(records_for(:nokogiri))
  end

  it "falls back to the generic walk for marker-bearing documents" do
    entity_xml = "<r><a>pre&nbsp;post</a></r>"
    records = Moxml.new(:leptris).materialize(entity_xml).to_a

    expect(records.map { |r| [r[:kind], r[:text]] }).to eq(
      [[:text, "pre"], [:entity_reference, "&nbsp;"], [:text, "post"],
       [:element, nil], [:element, nil]],
    )
  end

  it "materializes from any element subtree" do
    doc = Moxml.new(:nokogiri).parse(xml)
    title = doc.at_xpath("//*[local-name()='title']")
    records = title.materialize.to_a

    expect(records.map { |r| [r[:kind], r[:depth]] }).to eq([[:text, 1], [:element, 0]])
  end

  it "allocates no wrappers on the bulk path" do
    skip "leptris not installed" unless Moxml::Adapter.available?(:leptris)

    ctx = Moxml.new(:leptris)
    ctx.materialize(xml).to_a # warm
    GC.start
    before = GC.stat(:total_allocated_objects)
    ctx.materialize(xml).to_a
    allocated = GC.stat(:total_allocated_objects) - before
    node_count = ctx.parse(xml).materialize.count

    # Records themselves allocate (hash + FFI strings); the wrapper
    # tree does not: far fewer allocations than 2 wrappers per node.
    expect(allocated).to be < node_count * 24
  end
end
