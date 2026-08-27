# frozen_string_literal: true

require "spec_helper"

RSpec.describe "readonly parsing" do
  let(:xml) { '<r><a x="1">t</a></r>' }

  it "parses and reads normally" do
    doc = Moxml.new(:leptris).parse(xml, readonly: true)

    expect(doc.root.name).to eq("r")
    expect(doc.at_xpath("//a")["x"]).to eq("1")
    expect(doc.at_xpath("//a").text).to eq("t")
  end

  it "refuses mutations" do
    doc = Moxml.new(:leptris).parse(xml, readonly: true)

    expect { doc.root["y"] = "2" }.to raise_error(/ReadOnly/i)
  end

  it "is a no-op concept on other adapters" do
    doc = Moxml.new(:nokogiri).parse(xml, readonly: true)

    expect(doc.root.name).to eq("r")
  end
end
