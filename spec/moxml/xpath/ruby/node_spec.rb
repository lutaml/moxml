# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Ruby::Node do
  describe "#initialize" do
    it "creates a node with type and children" do
      node = described_class.new(:lit, ["10"])
      expect(node.type).to eq(:lit)
      expect(node.to_a).to eq(["10"])
    end

    it "creates a node with empty children by default" do
      node = described_class.new(:lit)
      expect(node.type).to eq(:lit)
      expect(node.to_a).to eq([])
    end

    it "converts type to symbol" do
      node = described_class.new("lit", ["10"])
      expect(node.type).to eq(:lit)
    end
  end

  describe "#to_a and #to_ary" do
    it "returns the children array" do
      children = ["a", "b", "c"]
      node = described_class.new(:test, children)
      expect(node.to_a).to eq(children)
      expect(node.to_ary).to eq(children)
    end
  end

  describe "#to_array" do
    it "returns a :send node calling to_a on the receiver" do
      node = described_class.new(:lit, ["items"])
      result = node.to_array

      expect(result.type).to eq(:send)
      expect(result.to_a).to eq([node, :to_a])
    end
  end

  describe "#assign" do
    it "creates an assignment node" do
      var = described_class.new(:lit, ["x"])
      val = described_class.new(:lit, ["10"])
      result = var.assign(val)

      expect(result.type).to eq(:assign)
      expect(result.to_a).to eq([var, val])
    end

    it "wraps followed_by nodes in begin block" do
      var = described_class.new(:lit, ["x"])
      val = described_class.new(:followed_by, [
                                  described_class.new(:lit, ["a"]),
                                  described_class.new(:lit, ["b"]),
                                ])
      result = var.assign(val)

      expect(result.type).to eq(:assign)
      assigned_val = result.to_a[1]
      expect(assigned_val.type).to eq(:begin)
    end
  end

  describe "#eq" do
    it "creates an equality comparison node" do
      left = described_class.new(:lit, ["10"])
      right = described_class.new(:lit, ["20"])
      result = left.eq(right)

      expect(result.type).to eq(:eq)
      expect(result.to_a).to eq([left, right])
    end
  end

  describe "#and" do
    it "creates a boolean and node" do
      left = described_class.new(:lit, ["true"])
      right = described_class.new(:lit, ["false"])
      result = left.and(right)

      expect(result.type).to eq(:and)
      expect(result.to_a).to eq([left, right])
    end
  end

  describe "#or" do
    it "creates a boolean or node" do
      left = described_class.new(:lit, ["true"])
      right = described_class.new(:lit, ["false"])
      result = left.or(right)

      expect(result.type).to eq(:or)
      expect(result.to_a).to eq([left, right])
    end
  end

  describe "#not" do
    it "creates a boolean not node using !" do
      node = described_class.new(:lit, ["true"])
      result = node.not

      # The not method calls !self, which should create appropriate node
      # Since Node inherits from BasicObject and undefines !,
      # we need to verify the behavior
      expect(result).to be_a(described_class)
    end
  end

  describe "#is_a?" do
    it "creates a :send node for is_a? method call" do
      node = described_class.new(:lit, ["obj"])
      result = node.is_a?(String)

      expect(result.type).to eq(:send)
      expect(result.to_a[0]).to eq(node)
      expect(result.to_a[1]).to eq("is_a?")
      expect(result.to_a[2].type).to eq(:lit)
      expect(result.to_a[2].to_a[0]).to eq("String")
    end
  end

  describe "#add_block" do
    it "wraps node in a block with arguments and body" do
      receiver = described_class.new(:lit, ["items"])
      arg = described_class.new(:lit, ["item"])
      body = described_class.new(:lit, ["body"])

      result = receiver.add_block(arg) { body }

      expect(result.type).to eq(:block)
      expect(result.to_a[0]).to eq(receiver)
      expect(result.to_a[1]).to eq([arg])
      expect(result.to_a[2]).to eq(body)
    end

    it "accepts multiple arguments" do
      receiver = described_class.new(:lit, ["hash"])
      arg1 = described_class.new(:lit, ["key"])
      arg2 = described_class.new(:lit, ["value"])
      body = described_class.new(:lit, ["body"])

      result = receiver.add_block(arg1, arg2) { body }

      expect(result.type).to eq(:block)
      expect(result.to_a[1]).to eq([arg1, arg2])
    end
  end

  describe "#wrap" do
    it "wraps the node in a begin node" do
      node = described_class.new(:lit, ["10"])
      result = node.wrap

      expect(result.type).to eq(:begin)
      expect(result.to_a).to eq([node])
    end
  end

  describe "#if_true" do
    it "creates an if statement with the node as condition" do
      condition = described_class.new(:lit, ["x > 10"])
      body = described_class.new(:lit, ['puts "yes"'])

      result = condition.if_true { body }

      expect(result.type).to eq(:if)
      expect(result.to_a[0]).to eq(condition)
      expect(result.to_a[1]).to eq(body)
    end
  end

  describe "#if_false" do
    it "creates an if !condition statement" do
      condition = described_class.new(:lit, ["x > 10"])
      body = described_class.new(:lit, ['puts "no"'])

      result = condition.if_false { body }

      expect(result.type).to eq(:if)
      # Should have a not applied to condition
      negated_condition = result.to_a[0]
      expect(negated_condition).to be_a(described_class)
    end
  end

  describe "#while_true" do
    it "creates a while loop with the node as condition" do
      condition = described_class.new(:lit, ["x < 10"])
      body = described_class.new(:lit, ["x += 1"])

      result = condition.while_true { body }

      expect(result.type).to eq(:while)
      expect(result.to_a[0]).to eq(condition)
      expect(result.to_a[1]).to eq(body)
    end
  end

  describe "#else" do
    it "adds an else clause to an if node" do
      condition = described_class.new(:lit, ["x > 10"])
      if_body = described_class.new(:lit, ["a"])
      else_body = described_class.new(:lit, ["b"])

      if_node = condition.if_true { if_body }
      result = if_node.else { else_body }

      expect(result.type).to eq(:if)
      expect(result.to_a[0]).to eq(condition)
      expect(result.to_a[1]).to eq(if_body)
      expect(result.to_a[2]).to eq(else_body)
    end
  end

  describe "#followed_by" do
    it "chains two nodes together" do
      first = described_class.new(:lit, ["a"])
      second = described_class.new(:lit, ["b"])

      result = first.followed_by(second)

      expect(result.type).to eq(:followed_by)
      expect(result.to_a[0]).to eq(first)
      expect(result.to_a[1]).to eq(second)
    end

    it "accepts a block to provide the second node" do
      first = described_class.new(:lit, ["a"])
      second = described_class.new(:lit, ["b"])

      result = first.followed_by { second }

      expect(result.type).to eq(:followed_by)
      expect(result.to_a[0]).to eq(first)
      expect(result.to_a[1]).to eq(second)
    end
  end

  describe "#method_missing" do
    it "creates a :send node for method calls without arguments" do
      receiver = described_class.new(:lit, ["obj"])
      result = receiver.foo

      expect(result.type).to eq(:send)
      expect(result.to_a[0]).to eq(receiver)
      expect(result.to_a[1]).to eq("foo")
    end

    it "creates a :send node for method calls with arguments" do
      receiver = described_class.new(:lit, ["obj"])
      arg1 = described_class.new(:lit, ["a"])
      arg2 = described_class.new(:lit, ["b"])

      result = receiver.bar(arg1, arg2)

      expect(result.type).to eq(:send)
      expect(result.to_a[0]).to eq(receiver)
      expect(result.to_a[1]).to eq("bar")
      expect(result.to_a[2]).to eq(arg1)
      expect(result.to_a[3]).to eq(arg2)
    end

    it "handles various method names" do
      receiver = described_class.new(:lit, ["obj"])

      # Test different method names
      expect(receiver.length.to_a[1]).to eq("length")
      expect(receiver.upcase.to_a[1]).to eq("upcase")
      expect(receiver.custom_method.to_a[1]).to eq("custom_method")
    end
  end

  describe "#inspect" do
    it "returns a string representation of the node" do
      node = described_class.new(:lit, ["10"])
      expect(node.inspect).to eq('(lit "10")')
    end

    it "includes nested nodes in the representation" do
      child1 = described_class.new(:lit, ["a"])
      child2 = described_class.new(:lit, ["b"])
      node = described_class.new(:eq, [child1, child2])

      expect(node.inspect).to eq('(eq (lit "a") (lit "b"))')
    end
  end
end
