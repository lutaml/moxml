# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::AST::Node do
  describe "abstract interface" do
    let(:node) { described_class.new }

    describe "#evaluate" do
      it "raises NotImplementedError" do
        context = Moxml::XPath::Context.new
        expect { node.evaluate(context) }.to raise_error(
          NotImplementedError,
          /#{described_class}#evaluate must be implemented by subclass/,
        )
      end
    end

    describe "#constant?" do
      it "returns false by default" do
        expect(node.constant?).to be(false)
      end
    end

    describe "#result_type" do
      it "returns :unknown by default" do
        expect(node.result_type).to eq(:unknown)
      end
    end

    describe "#inspect" do
      it "returns class name representation" do
        expect(node.inspect).to match(/^#<#{Regexp.escape(described_class.name)} @type=/)
      end
    end

    describe "#to_s" do
      it "aliases #inspect" do
        expect(node.to_s).to eq(node.inspect)
      end
    end
  end

  describe "concrete implementation" do
    # Create a test subclass to verify the interface works
    let(:test_class) do
      Class.new(described_class) do
        def initialize(value)
          @value = value
        end

        def evaluate(_context)
          @value
        end

        def constant?
          true
        end

        def result_type
          :string
        end
      end
    end

    it "can be subclassed with custom evaluate" do
      node = test_class.new("test_value")
      context = Moxml::XPath::Context.new

      expect(node.evaluate(context)).to eq("test_value")
    end

    it "can override constant?" do
      node = test_class.new("test")
      expect(node.constant?).to be(true)
    end

    it "can override result_type" do
      node = test_class.new("test")
      expect(node.result_type).to eq(:string)
    end
  end
end
