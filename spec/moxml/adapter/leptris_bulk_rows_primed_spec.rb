# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end

require "moxml/adapter/leptris"
return unless Moxml::Adapter::Leptris::PRIMED_BULK_ROWS

require "spec_helper"

# The primed bulk rows lane: the adapter hands the binding's bulk
# face the moxml Context and adapter at the eval crossing, rows are
# born primed, and an all-native result carries the BulkIdentityRows
# mark NodeSet's row loop keys on (yield in place, no per-row wrap).
RSpec.describe "leptris xpath primed bulk rows" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) do
    ctx.parse(<<~XML)
      <root>
        <item id="1">alpha</item>
        <item id="2">beta</item>
      </root>
    XML
  end

  it "arms the primed-bulk gate on a capable binding" do
    expect(Moxml::Adapter::Leptris::PRIMED_BULK_ROWS).to be(true)
  end

  it "registers the parse context for the binding document" do
    binding_doc = doc.native
    expect(Moxml::Adapter::Leptris.native_doc_context(binding_doc)).to be(ctx)
  end

  it "marks all-native xpath results" do
    rows = doc.xpath("//item")
    expect(rows.native_nodes).to respond_to(:bulk_identity_rows?)
    expect(rows.native_nodes.bulk_identity_rows?).to be(true)
  end

  it "leaves attribute-row results unmarked" do
    rows = doc.xpath("//item/@id")
    marked = rows.native_nodes.respond_to?(:bulk_identity_rows?) &&
      rows.native_nodes.bulk_identity_rows?
    expect(marked).to be(false)
  end

  it "yields rows born primed with the parse context" do
    doc.xpath("//item").each do |node|
      expect(node.instance_variable_get(:@context)).to be(ctx)
      expect(node.instance_variable_get(:@native)).to equal(node)
    end
  end

  it "yields rows that answer structural reads immediately" do
    doc.xpath("//item").each do |node|
      expect(node.parent.name).to eq("root")
      expect(node.document).not_to be_nil
    end
  end

  it "keeps one Ruby object per address across queries" do
    first = doc.xpath("//item").to_a
    second = doc.xpath("//item").to_a
    first.zip(second).each { |a, b| expect(a).to equal(b) }
  end

  it "keeps attribute rows wrapping to Attribute on the primed lane" do
    names = doc.xpath("//item/@id").map { |n| [n.class, n.name, n.value] }
    expect(names).to eq([
                          [Moxml::Wrappers::Attribute, "id", "1"],
                          [Moxml::Wrappers::Attribute, "id", "2"],
                        ])
  end
end
