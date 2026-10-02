# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Nokogiri-compatible at/search sugar" do
  let(:doc) do
    Moxml.parse(<<~XML)
      <root xmlns="http://example.com/ns">
        <item id="a"><name>one</name></item>
        <item id="b"><name>two</name></item>
      </root>
    XML
  end

  it "at returns the first match like Nokogiri" do
    node = doc.at("//xmlns:item")
    expect(node["id"]).to eq("a")
  end

  it "at on document delegates to root search" do
    expect(doc.at("//xmlns:name").text).to eq("one")
  end

  it "search returns all matches" do
    expect(doc.search("//xmlns:item").size).to eq(2)
  end

  it "at returns nil when nothing matches" do
    expect(doc.at("//xmlns:missing")).to be_nil
  end

  it "at works on element nodes" do
    item = doc.at("//xmlns:item[@id='b']")
    expect(item.at("xmlns:name").text).to eq("two")
  end
end
