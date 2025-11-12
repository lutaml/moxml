# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath do
  describe "module structure" do
    it "has Engine class" do
      expect(defined?(Moxml::XPath::Engine)).to eq("constant")
    end

    it "has AST module" do
      expect(defined?(Moxml::XPath::AST)).to eq("constant")
    end

    it "has AST::Node class" do
      expect(defined?(Moxml::XPath::AST::Node)).to eq("constant")
    end
  end

  describe "error classes" do
    it "has Error class inheriting from XPathError" do
      expect(Moxml::XPath::Error).to be < Moxml::XPathError
    end

    it "has SyntaxError class" do
      expect(defined?(Moxml::XPath::SyntaxError)).to eq("constant")
      expect(Moxml::XPath::SyntaxError).to be < Moxml::XPath::Error
    end

    it "has EvaluationError class" do
      expect(defined?(Moxml::XPath::EvaluationError)).to eq("constant")
      expect(Moxml::XPath::EvaluationError).to be < Moxml::XPath::Error
    end

    it "has FunctionError class" do
      expect(defined?(Moxml::XPath::FunctionError)).to eq("constant")
      expect(Moxml::XPath::FunctionError).to be < Moxml::XPath::Error
    end

    it "has NodeTypeError class" do
      expect(defined?(Moxml::XPath::NodeTypeError)).to eq("constant")
      expect(Moxml::XPath::NodeTypeError).to be < Moxml::XPath::Error
    end
  end

  describe Moxml::XPath::Engine do
    let(:xml) { File.read("spec/moxml/xpath/fixtures/sample.xml") }
    let(:doc) { Moxml.new.parse(xml) }
    let(:engine) { described_class.new(doc) }

    describe "#initialize" do
      it "accepts a document" do
        expect(engine.document).to eq(doc)
      end
    end

    describe "#evaluate" do
      it "raises NotImplementedError in Phase 1.0" do
        expect { engine.evaluate("//book") }
          .to raise_error(NotImplementedError, /Phase 1.1/)
      end
    end

    describe "#valid?" do
      it "returns false for syntax errors" do
        allow(engine).to receive(:evaluate)
          .and_raise(Moxml::XPath::SyntaxError.new("Invalid"))
        expect(engine.valid?("invalid[[[")).to be false
      end

      it "returns true for valid expressions" do
        allow(engine).to receive(:evaluate).and_return([])
        expect(engine.valid?("//book")).to be true
      end
    end
  end
end