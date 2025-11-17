# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Context do
  let(:context) { described_class.new }

  describe "#evaluate" do
    it "evaluates simple Ruby code" do
      result = context.evaluate("1 + 1")
      expect(result).to eq(2)
    end

    it "evaluates string expressions" do
      result = context.evaluate('"hello" + " world"')
      expect(result).to eq("hello world")
    end

    it "evaluates boolean expressions" do
      result = context.evaluate("true && false")
      expect(result).to be(false)
    end

    it "evaluates arithmetic expressions" do
      result = context.evaluate("10 * 5 + 3")
      expect(result).to eq(53)
    end

    it "evaluates method calls" do
      result = context.evaluate('"hello".upcase')
      expect(result).to eq("HELLO")
    end

    it "evaluates array operations" do
      result = context.evaluate("[1, 2, 3].map { |x| x * 2 }")
      expect(result).to eq([2, 4, 6])
    end

    it "evaluates variable assignments and usage" do
      code = <<~RUBY
        x = 10
        y = 20
        x + y
      RUBY
      result = context.evaluate(code)
      expect(result).to eq(30)
    end

    it "evaluates conditional statements" do
      code = <<~RUBY
        x = 15
        if x > 10
          "big"
        else
          "small"
        end
      RUBY
      result = context.evaluate(code)
      expect(result).to eq("big")
    end

    it "evaluates loops" do
      code = <<~RUBY
        sum = 0
        [1, 2, 3, 4, 5].each do |n|
          sum += n
        end
        sum
      RUBY
      result = context.evaluate(code)
      expect(result).to eq(15)
    end

    it "returns the value of the last expression" do
      code = <<~RUBY
        x = 10
        y = 20
        x
        y
      RUBY
      result = context.evaluate(code)
      expect(result).to eq(20)
    end

    it "handles lambda expressions" do
      code = "lambda { |x| x * 2 }.call(5)"
      result = context.evaluate(code)
      expect(result).to eq(10)
    end

    it "handles proc expressions" do
      code = "proc { |x| x + 1 }.call(9)"
      result = context.evaluate(code)
      expect(result).to eq(10)
    end

    it "raises SyntaxError for invalid Ruby code" do
      expect do
        context.evaluate("def invalid syntax")
      end.to raise_error(SyntaxError)
    end

    it "raises NameError for undefined variables" do
      expect do
        context.evaluate("undefined_variable")
      end.to raise_error(NameError)
    end

    it "provides isolated binding between calls" do
      context.evaluate("x = 100")
      # Each evaluate call should have access to previously defined variables
      # in the same context's binding
      result = context.evaluate("x")
      expect(result).to eq(100)
    end

    it "can define and call methods" do
      code = <<~RUBY
        def add(a, b)
          a + b
        end
        add(3, 4)
      RUBY
      result = context.evaluate(code)
      expect(result).to eq(7)
    end

    it "handles complex nested structures" do
      code = <<~RUBY
        data = { a: [1, 2, 3], b: [4, 5, 6] }
        data[:a].map { |x| x * 2 } + data[:b].map { |x| x * 3 }
      RUBY
      result = context.evaluate(code)
      expect(result).to eq([2, 4, 6, 12, 15, 18])
    end

    it "returns lambda/proc objects" do
      result = context.evaluate("lambda { |x| x * 2 }")
      expect(result).to be_a(Proc)
      expect(result.call(5)).to eq(10)
    end

    it "handles begin/rescue/end blocks" do
      code = <<~RUBY
        begin
          1 / 0
        rescue ZeroDivisionError
          "error caught"
        end
      RUBY
      result = context.evaluate(code)
      expect(result).to eq("error caught")
    end
  end

  describe "binding isolation" do
    it "maintains separate bindings for different context instances" do
      context1 = described_class.new
      context2 = described_class.new

      context1.evaluate("x = 100")

      # context2 should not have access to context1's variables
      expect { context2.evaluate("x") }.to raise_error(NameError)
    end

    it "maintains state within a single context" do
      context.evaluate("counter = 0")
      context.evaluate("counter += 1")
      context.evaluate("counter += 1")
      result = context.evaluate("counter")

      expect(result).to eq(2)
    end
  end

  describe "edge cases" do
    it "handles empty string" do
      result = context.evaluate("")
      expect(result).to be_nil
    end

    it "handles nil literal" do
      result = context.evaluate("nil")
      expect(result).to be_nil
    end

    it "handles true literal" do
      result = context.evaluate("true")
      expect(result).to be(true)
    end

    it "handles false literal" do
      result = context.evaluate("false")
      expect(result).to be(false)
    end

    it "handles multiline strings" do
      code = <<~RUBY
        str = <<~TEXT
          Hello
          World
        TEXT
        str.strip
      RUBY
      result = context.evaluate(code)
      expect(result).to eq("Hello\nWorld")
    end
  end
end
