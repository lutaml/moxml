# frozen_string_literal: true

begin
  require "leptris"
rescue LoadError
  # Leptris gem not available - skip all specs in this file
  return
end

require "moxml/adapter/leptris"

# leptris-ruby#529: the multi-result native XPath lane routes through
# Document#xpath_result_rows_bulk when the binding answers it — the
# whole node-set in ONE C crossing instead of one crossing per row.
# The rows keep the eager lane's contract (registered wrapper
# klasses, ResultAttr/ResultText synthetic rows, scalar pass-through
# on non-node-set results), so every consumer-visible shape is
# unchanged; what pins here is the routing gate and those shapes.
RSpec.describe "leptris xpath bulk rows routing" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) do
    ctx.parse(<<~XML)
      <root>
        <item id="1">alpha</item>
        <item id="2">beta</item>
        <!-- note -->
      </root>
    XML
  end

  it "arms the gate on the current binding" do
    expect(Leptris::XML::Native.respond_to?(:xpath_result_rows_bulk)).to be(true)
    expect(Leptris::XML::Document.method_defined?(:xpath_result_rows_bulk)).to be(true)
    expect(Moxml::Adapter::Leptris::BULK_XPATH_ROWS).to be(true)
  end

  it "answers multi-result queries with wrapped natives in order" do
    set = doc.xpath("//item")
    expect(set).to be_a(Moxml::NodeSet)
    expect(set.size).to eq(2)
    expect(set.map(&:name)).to eq(%w[item item])
    expect(set.map(&:text)).to eq(%w[alpha beta])
    expect(set.first).to be_a(Moxml::Element)
  end

  it "keeps attribute rows as Attribute wrappers" do
    attrs = doc.xpath("//item/@id")
    expect(attrs.map(&:name)).to eq(%w[id id])
    expect(attrs.map(&:value)).to eq(%w[1 2])
    expect(attrs.first).to be_a(Moxml::Attribute)
  end

  it "keeps mixed element and comment rows in document order" do
    set = doc.xpath("/root/node()").grep_v(Moxml::Text)
    expect(set.map { |n| n.is_a?(Moxml::Comment) ? :comment : n.name.to_sym })
      .to eq(%i[item item comment])
  end

  it "passes scalars through unwrapped" do
    expect(doc.xpath("count(//item)")).to eq(2.0)
    expect(doc.xpath("string(//item)")).to eq("alpha")
    expect(doc.xpath("//item[@id='9']")).to be_a(Moxml::NodeSet)
    expect(doc.xpath("//item[@id='9']").empty?).to be(true)
  end

  it "resolves one address to one Ruby object across queries" do
    first = doc.xpath("//item").first
    again = doc.xpath("//item").first
    expect(again).to be(first)
  end

  # leptris-ruby#527: the count row is one evaluation plus a size
  # read — it must not pay the per-row mint.
  describe "row materialization is deferred" do
    def bulk_calls
      calls = 0
      tp = TracePoint.new(:c_call) do |t|
        calls += 1 if t.method_id == :xpath_result_rows_bulk
      end
      tp.enable { yield }
      calls
    end

    it "answers size without minting rows, minting on first iteration" do
      set = nil
      expect(bulk_calls { set = doc.xpath("//item") }).to eq(0)
      expect(bulk_calls { set.size }).to eq(0)
      expect(bulk_calls { set.empty? }).to eq(0)
      expect(bulk_calls { set.to_a }).to eq(1)
      expect(set.map(&:name)).to eq(%w[item item])
    end

    it "keeps row identity and order through the deferred mint" do
      set = doc.xpath("//item")
      expect(set.map(&:text)).to eq(%w[alpha beta])
      expect(set.first).to be(doc.xpath("//item").first)
    end
  end
end
