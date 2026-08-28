# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Document#free" do
  let(:xml) { '<r><a x="1">t</a></r>' }

  it "frees native memory deterministically (issue #134)" do
    doc = Moxml.new(:leptris).parse(xml)
    expect(doc.root.name).to eq("r")

    expect(doc.free).to be_nil
    expect { doc.root }.to raise_error(Leptris::XML::UseAfterFreeError)
  end

  it "is a no-op on GC-managed engines" do
    doc = Moxml.new(:nokogiri).parse(xml)

    expect(doc.free).to be_nil
    expect(doc.root.name).to eq("r")
  end
end
