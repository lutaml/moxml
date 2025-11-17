# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Ruby::Generator do
  let(:generator) { described_class.new }
  let(:node_class) { Moxml::XPath::Ruby::Node }

  describe "#process" do
    it "dispatches to the appropriate on_* method based on node type" do
      node = node_class.new(:lit, ["10"])
      expect(generator.process(node)).to eq("10")
    end
  end

  describe "#on_followed_by" do
    it "joins multiple statements with blank lines" do
      stmt1 = node_class.new(:lit, ["a"])
      stmt2 = node_class.new(:lit, ["b"])
      stmt3 = node_class.new(:lit, ["c"])
      node = node_class.new(:followed_by, [stmt1, stmt2, stmt3])

      result = generator.process(node)
      expect(result).to eq("a\n\nb\n\nc")
    end

    it "processes each child node" do
      assign1 = node_class.new(:assign, [
                                 node_class.new(:lit, ["x"]),
                                 node_class.new(:lit, ["10"]),
                               ])
      assign2 = node_class.new(:assign, [
                                 node_class.new(:lit, ["y"]),
                                 node_class.new(:lit, ["20"]),
                               ])
      node = node_class.new(:followed_by, [assign1, assign2])

      result = generator.process(node)
      expect(result).to eq("x = 10\n\ny = 20")
    end
  end

  describe "#on_assign" do
    it "generates an assignment statement" do
      var = node_class.new(:lit, ["x"])
      val = node_class.new(:lit, ["10"])
      node = node_class.new(:assign, [var, val])

      result = generator.process(node)
      expect(result).to eq("x = 10")
    end

    it "handles complex expressions" do
      var = node_class.new(:lit, ["result"])
      val = node_class.new(:send, [
                             node_class.new(:lit, ["a"]),
                             "+",
                             node_class.new(:lit, ["b"]),
                           ])
      node = node_class.new(:assign, [var, val])

      result = generator.process(node)
      expect(result).to eq("result = a.+(b)")
    end
  end

  describe "#on_massign" do
    it "generates a multiple assignment statement" do
      vars = [
        node_class.new(:lit, ["x"]),
        node_class.new(:lit, ["y"]),
      ]
      val = node_class.new(:lit, ["[1, 2]"])
      node = node_class.new(:massign, [vars, val])

      result = generator.process(node)
      expect(result).to eq("x, y = [1, 2]")
    end

    it "handles three or more variables" do
      vars = [
        node_class.new(:lit, ["a"]),
        node_class.new(:lit, ["b"]),
        node_class.new(:lit, ["c"]),
      ]
      val = node_class.new(:lit, ["[1, 2, 3]"])
      node = node_class.new(:massign, [vars, val])

      result = generator.process(node)
      expect(result).to eq("a, b, c = [1, 2, 3]")
    end
  end

  describe "#on_begin" do
    it "wraps code in a begin/end block" do
      body = node_class.new(:lit, ["x + y"])
      node = node_class.new(:begin, [body])

      result = generator.process(node)
      expect(result).to include("begin")
      expect(result).to include("x + y")
      expect(result).to include("end")
    end
  end

  describe "#on_eq" do
    it "generates an equality comparison" do
      left = node_class.new(:lit, ["x"])
      right = node_class.new(:lit, ["10"])
      node = node_class.new(:eq, [left, right])

      result = generator.process(node)
      expect(result).to eq("x == 10")
    end

    it "handles complex expressions on both sides" do
      left = node_class.new(:send, [
                              node_class.new(:lit, ["a"]),
                              "length",
                            ])
      right = node_class.new(:lit, ["5"])
      node = node_class.new(:eq, [left, right])

      result = generator.process(node)
      expect(result).to eq("a.length == 5")
    end
  end

  describe "#on_and" do
    it "generates a boolean and expression" do
      left = node_class.new(:lit, ["x"])
      right = node_class.new(:lit, ["y"])
      node = node_class.new(:and, [left, right])

      result = generator.process(node)
      expect(result).to eq("x && y")
    end
  end

  describe "#on_or" do
    it "generates a boolean or expression with parentheses" do
      left = node_class.new(:lit, ["x"])
      right = node_class.new(:lit, ["y"])
      node = node_class.new(:or, [left, right])

      result = generator.process(node)
      expect(result).to eq("(x || y)")
    end
  end

  describe "#on_if" do
    it "generates an if statement without else" do
      condition = node_class.new(:lit, ["x > 10"])
      body = node_class.new(:lit, ['puts "yes"'])
      node = node_class.new(:if, [condition, body])

      result = generator.process(node)
      expect(result).to include("if x > 10")
      expect(result).to include('puts "yes"')
      expect(result).to include("end")
      expect(result).not_to include("else")
    end

    it "generates an if/else statement when else_body is present" do
      condition = node_class.new(:lit, ["x > 10"])
      body = node_class.new(:lit, ['puts "yes"'])
      else_body = node_class.new(:lit, ['puts "no"'])
      node = node_class.new(:if, [condition, body, else_body])

      result = generator.process(node)
      expect(result).to include("if x > 10")
      expect(result).to include('puts "yes"')
      expect(result).to include("else")
      expect(result).to include('puts "no"')
      expect(result).to include("end")
    end
  end

  describe "#on_while" do
    it "generates a while loop" do
      condition = node_class.new(:lit, ["x < 10"])
      body = node_class.new(:lit, ["x += 1"])
      node = node_class.new(:while, [condition, body])

      result = generator.process(node)
      expect(result).to include("while x < 10")
      expect(result).to include("x += 1")
      expect(result).to include("end")
    end
  end

  describe "#on_send" do
    it "generates a method call without receiver" do
      node = node_class.new(:send,
                            [nil, "puts", node_class.new(:string, ["hello"])])

      result = generator.process(node)
      expect(result).to eq('puts("hello")')
    end

    it "generates a method call with receiver" do
      receiver = node_class.new(:lit, ["str"])
      node = node_class.new(:send, [receiver, "upcase"])

      result = generator.process(node)
      expect(result).to eq("str.upcase")
    end

    it "generates a method call with receiver and arguments" do
      receiver = node_class.new(:lit, ["arr"])
      arg = node_class.new(:lit, ["0"])
      node = node_class.new(:send, [receiver, "at", arg])

      result = generator.process(node)
      expect(result).to eq("arr.at(0)")
    end

    it "handles multiple arguments" do
      receiver = node_class.new(:lit, ["str"])
      arg1 = node_class.new(:lit, ["0"])
      arg2 = node_class.new(:lit, ["5"])
      node = node_class.new(:send, [receiver, "slice", arg1, arg2])

      result = generator.process(node)
      expect(result).to eq("str.slice(0, 5)")
    end

    it "handles bracket notation for array access" do
      receiver = node_class.new(:lit, ["arr"])
      arg = node_class.new(:lit, ["0"])
      node = node_class.new(:send, [receiver, "[]", arg])

      result = generator.process(node)
      expect(result).to eq("arr[0]")
    end

    it "handles bracket notation without arguments" do
      receiver = node_class.new(:lit, ["arr"])
      node = node_class.new(:send, [receiver, "[]"])

      result = generator.process(node)
      expect(result).to eq("arr[]")
    end
  end

  describe "#on_block" do
    it "generates a block with single argument" do
      receiver = node_class.new(:send, [
                                  node_class.new(:lit, ["items"]),
                                  "each",
                                ])
      arg = node_class.new(:lit, ["item"])
      body = node_class.new(:send, [
                              nil,
                              "puts",
                              node_class.new(:lit, ["item"]),
                            ])
      node = node_class.new(:block, [receiver, [arg], body])

      result = generator.process(node)
      expect(result).to include("items.each do |item|")
      expect(result).to include("puts(item)")
      expect(result).to include("end")
    end

    it "generates a block with multiple arguments" do
      receiver = node_class.new(:send, [
                                  node_class.new(:lit, ["hash"]),
                                  "each",
                                ])
      arg1 = node_class.new(:lit, ["key"])
      arg2 = node_class.new(:lit, ["value"])
      body = node_class.new(:lit, ["body"])
      node = node_class.new(:block, [receiver, [arg1, arg2], body])

      result = generator.process(node)
      expect(result).to include("hash.each do |key, value|")
      expect(result).to include("body")
    end

    it "handles blocks without body" do
      receiver = node_class.new(:send, [
                                  node_class.new(:lit, ["items"]),
                                  "each",
                                ])
      arg = node_class.new(:lit, ["item"])
      node = node_class.new(:block, [receiver, [arg], nil])

      result = generator.process(node)
      expect(result).to include("items.each do |item|")
      expect(result).to include("end")
    end
  end

  describe "#on_range" do
    it "generates a range expression" do
      start = node_class.new(:lit, ["1"])
      stop = node_class.new(:lit, ["10"])
      node = node_class.new(:range, [start, stop])

      result = generator.process(node)
      expect(result).to eq("(1..10)")
    end

    it "handles complex expressions as range boundaries" do
      start = node_class.new(:send, [
                               node_class.new(:lit, ["arr"]),
                               "first",
                             ])
      stop = node_class.new(:send, [
                              node_class.new(:lit, ["arr"]),
                              "last",
                            ])
      node = node_class.new(:range, [start, stop])

      result = generator.process(node)
      expect(result).to eq("(arr.first..arr.last)")
    end
  end

  describe "#on_string" do
    it "generates a string literal with proper escaping" do
      node = node_class.new(:string, ["hello world"])

      result = generator.process(node)
      expect(result).to eq('"hello world"')
    end

    it "properly escapes special characters" do
      node = node_class.new(:string, ['hello "world"'])

      result = generator.process(node)
      expect(result).to eq('"hello \"world\""')
    end

    it "handles newlines" do
      node = node_class.new(:string, ["hello\nworld"])

      result = generator.process(node)
      expect(result).to eq('"hello\nworld"')
    end
  end

  describe "#on_symbol" do
    it "generates a symbol literal" do
      node = node_class.new(:symbol, ["test"])

      result = generator.process(node)
      expect(result).to eq(":test")
    end

    it "handles symbols with special characters" do
      node = node_class.new(:symbol, ["test_symbol"])

      result = generator.process(node)
      expect(result).to eq(":test_symbol")
    end
  end

  describe "#on_lit" do
    it "returns the literal value as-is" do
      node = node_class.new(:lit, ["42"])

      result = generator.process(node)
      expect(result).to eq("42")
    end

    it "handles variable names" do
      node = node_class.new(:lit, ["my_var"])

      result = generator.process(node)
      expect(result).to eq("my_var")
    end

    it "handles any string literal" do
      node = node_class.new(:lit, ["some_expression"])

      result = generator.process(node)
      expect(result).to eq("some_expression")
    end
  end

  describe "integration tests" do
    it "generates valid Ruby code for complex expressions" do
      # Create: x = 10; if x > 5; puts "big"; else; puts "small"; end
      x_var = node_class.new(:lit, ["x"])
      ten = node_class.new(:lit, ["10"])
      assignment = x_var.assign(ten)

      condition = node_class.new(:send,
                                 [x_var, ">", node_class.new(:lit, ["5"])])
      if_body = node_class.new(:send,
                               [nil, "puts", node_class.new(:string, ["big"])])
      else_body = node_class.new(:send,
                                 [nil, "puts",
                                  node_class.new(:string, ["small"])])
      if_stmt = node_class.new(:if, [condition, if_body, else_body])

      program = assignment.followed_by(if_stmt)

      code = generator.process(program)
      expect(code).to be_a(String)

      # Verify code can be parsed (basic syntax check)
      expect { eval("lambda { #{code} }") }.not_to raise_error
    end

    it "generates code for nested blocks" do
      # Create: [1,2,3].each { |x| puts x }
      arr = node_class.new(:lit, ["[1,2,3]"])
      each_call = node_class.new(:send, [arr, "each"])
      arg = node_class.new(:lit, ["x"])
      body = node_class.new(:send, [nil, "puts", node_class.new(:lit, ["x"])])
      block = node_class.new(:block, [each_call, [arg], body])

      code = generator.process(block)
      expect(code).to include("[1,2,3].each do |x|")
      expect(code).to include("puts(x)")
    end
  end
end
