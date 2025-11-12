# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::AST::Node do
  describe "abstract interface" do
    let(:node) { described_class.new }

    describe "#evaluate" do
      it "raises NotImplementedError" do
        context = double("context")
        expect { node.evaluate(context) }
          .to raise_error(NotImplementedError, /must be implemented by subclass/)
      end
    end

    describe "#constant?" do
      it "returns false by default" do
        expect(node.constant?).to be false
      end
    end

    describe "#result_type" do
      it "returns :unknown by default" do
        expect(node.result_type).to eq(:unknown)
      end
    end

    describe "#inspect" do
      it "returns class name representation" do
        expect(node.inspect).to match(/Moxml::XPath::AST::Node/)
      end
    end

    describe "#to_s" do
      it "aliases #inspect" do
        expect(node.to_s).to eq(node.inspect)
      end
    end
  end

  describe "concrete implementation" do
    # Example concrete node for testing
    let(:concrete_class) do
      Class.new(described_class) do
        def evaluate(_context)
          "concrete result"
        end

        def constant?
          true
        end

        def result_type
          :string
        end
      end
    end

    let(:concrete_node) { concrete_class.new }

    it "can be subclassed with custom evaluate" do
      context = double("context")
      expect(concrete_node.evaluate(context)).to eq("concrete result")
    end

    it "can override constant?" do
      expect(concrete_node.constant?).to be true
    end

    it "can override result_type" do
      expect(concrete_node.result_type).to eq(:string)
    end
  end
end