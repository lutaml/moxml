# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Attribute do
  let(:context) { Moxml.new }
  let(:doc) { context.parse('<root id="123" class="test"/>') }
  let(:element) { doc.root }

  describe "#name" do
    it "returns attribute name" do
      attr = element.attributes.first
      expect(%w[id class]).to include(attr.name)
    end
  end

  describe "#value" do
    it "returns attribute value" do
      id_attr = element.attributes.find { |a| a.name == "id" }
      expect(id_attr.value).to eq("123")
    end
  end

  describe "#to_s" do
    it "returns string representation" do
      attr = element.attributes.first
      expect(attr.to_s).to match(/\w+="\w+"/)
    end
  end

  describe "#element" do
    it "returns wrapped Element" do
      attr = element.attributes.find { |a| a.name == "id" }
      parent = attr.element
      expect(parent).to be_a(Moxml::Element)
      expect(parent.name).to eq("root")
    end
  end

  describe "#content" do
    it "returns attribute value" do
      attr = element.attributes.find { |a| a.name == "id" }
      expect(attr.content).to eq("123")
    end
  end
end
