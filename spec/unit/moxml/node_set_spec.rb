# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::NodeSet do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root><child/><child/><child/></root>") }

  describe "#length" do
    it "returns number of nodes" do
      nodes = doc.root.children
      expect(nodes.length).to eq(3)
    end
  end

  describe "#[]" do
    it "accesses nodes by index" do
      nodes = doc.root.children
      expect(nodes[0]).to be_a(Moxml::Element)
      expect(nodes[0].name).to eq("child")
    end
  end

  describe "#each" do
    it "iterates over nodes" do
      nodes = doc.root.children
      count = 0
      nodes.each { |_node| count += 1 }
      expect(count).to eq(3)
    end
  end

  describe "#empty?" do
    it "returns true when empty" do
      nodes = doc.create_element("empty").children
      expect(nodes).to be_empty
    end
  end
end
