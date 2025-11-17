# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Comment do
  let(:context) { Moxml.new }
  let(:doc) { context.parse("<root><!-- test comment --></root>") }

  describe "#content" do
    it "returns comment content" do
      comment = doc.root.children.first
      expect(comment).to be_a(described_class)
      expect(comment.content).to eq(" test comment ")
    end
  end

  describe "#to_xml" do
    it "serializes to XML comment" do
      comment = doc.root.children.first
      expect(comment.to_xml).to eq("<!-- test comment -->")
    end
  end

  describe "creation" do
    it "creates a comment node" do
      comment = doc.create_comment("new comment")
      expect(comment).to be_a(described_class)
      expect(comment.content).to eq("new comment")
    end
  end
end
