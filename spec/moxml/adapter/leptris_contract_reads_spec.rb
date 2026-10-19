# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#460 — the Identity contract reads ride the C faces
# by plain dispatch (NativeNode subclasses inherit the C-defined
# name/content since binding 1.9.359). The wrapper memo stays; the
# ADAPTER CROSSING (bind_call through node_name/text_content) goes.
RSpec.describe "leptris Identity contract reads" do
  let(:ctx) { Moxml.new(:leptris) }

  before do
    unless Moxml::Adapter::Leptris::NATIVE_READ_LAYER &&
        Leptris::XML::NativeNode.method_defined?(:name) &&
        Leptris::XML::NativeNode.method_defined?(:content)
      skip "binding #{defined?(Leptris) && Leptris::VERSION} lacks the C contract faces"
    end
  end

  def bust(node, *ivars)
    ivars.each do |iv|
      node.remove_instance_variable(iv) if node.instance_variable_defined?(iv)
    end
  end

  def forbid_crossing!(method)
    singleton = Moxml::Adapter::Leptris.singleton_class
    singleton.send(:alias_method, :"#{method}_without_460", method)
    singleton.send(:define_method, method) { |*| raise "adapter #{method} crossing" }
    method
  end

  def restore_crossing!(method)
    singleton = Moxml::Adapter::Leptris.singleton_class
    singleton.send(:alias_method, method, :"#{method}_without_460")
    singleton.send(:remove_method, :"#{method}_without_460")
  end

  describe "element#name" do
    it "answers without the adapter node_name crossing" do
      unless Leptris::XML::NativeNode.method_defined?(:name_read)
        skip "binding #{Leptris::VERSION} has no name_read face (adapter path is correct there)"
      end
      doc = ctx.parse('<root><item id="1">v</item></root>')
      el = doc.root.children.first
      expect(el.native).to be_a(Leptris::XML::NativeNode)

      bust(el, :@name)
      forbid_crossing!(:node_name)
      begin
        expect(el.name).to eq("item")
      ensure
        restore_crossing!(:node_name)
      end
    end

    it "answers the local name for prefixed elements (cross-adapter contract)" do
      doc = ctx.parse('<root xmlns:ns="urn:u"><ns:p/></root>')
      el = doc.root.children.first
      bust(el, :@name)
      expect(el.name).to eq("p")
    end

    it "memoizes: warm reads return the same String" do
      doc = ctx.parse("<root><item/></root>")
      el = doc.root.children.first
      first = el.name
      expect(el.name).to equal(first)
    end

    it "re-reads after name=" do
      doc = ctx.parse("<root><item/></root>")
      el = doc.root.children.first
      el.name = "renamed"
      expect(el.name).to eq("renamed")
    end
  end

  describe "text#content" do
    it "answers without the adapter text_content crossing" do
      unless Leptris::XML::NativeNode.method_defined?(:text_read)
        skip "binding #{Leptris::VERSION} has no text_read face (adapter path is correct there)"
      end
      doc = ctx.parse("<root><item>v</item></root>")
      tx = doc.root.children.first.children.first
      expect(tx.native).to be_a(Leptris::XML::NativeNode)

      bust(tx, :@content)
      forbid_crossing!(:text_content)
      begin
        expect(tx.content).to eq("v")
      ensure
        restore_crossing!(:text_content)
      end
    end

    it "memoizes: warm reads return the same String" do
      doc = ctx.parse("<root><item>v</item></root>")
      tx = doc.root.children.first.children.first
      first = tx.content
      expect(tx.content).to equal(first)
    end

    it "re-reads after content=" do
      doc = ctx.parse("<root><item>v</item></root>")
      tx = doc.root.children.first.children.first
      tx.content = "changed"
      expect(tx.content).to eq("changed")
    end

    it "restores entities on entity-bearing documents" do
      ctx2 = Moxml.new(:leptris) { |c| c.restore_entities = true }
      doc = ctx2.parse("<root><item>a &amp; b</item></root>")
      tx = doc.root.children.first.children.first
      bust(tx, :@content)
      expect(tx.content).to eq("a & b")
    end
  end

  describe "the untouched faces" do
    it "keeps text wrappers named text" do
      doc = ctx.parse("<root><item>v</item></root>")
      tx = doc.root.children.first.children.first
      expect(tx.name).to eq("text")
    end

    it "keeps element#text on the existing path" do
      doc = ctx.parse("<root><item>v</item></root>")
      el = doc.root.children.first
      expect(el.text).to eq("v")
    end
  end

  describe "children" do
    it "answers without the adapter children crossing (children_read)" do
      unless Leptris::XML::NativeNode.method_defined?(:children_read)
        skip "binding #{Leptris::VERSION} has no children_read face"
      end
      doc = ctx.parse("<root><item>v</item></root>")
      el = doc.root.children.first

      singleton = Moxml::Adapter::Leptris.singleton_class
      singleton.send(:alias_method, :children_without_walk, :children)
      singleton.send(:define_method, :children) { |*| raise "adapter children crossing" }
      begin
        kids = el.children
        expect(kids.to_a.map(&:name)).to eq(["text"])
      ensure
        singleton.send(:alias_method, :children, :children_without_walk)
        singleton.send(:remove_method, :children_without_walk)
      end
    end

    it "returns a NodeSet carrying the contract wrappers" do
      doc = ctx.parse("<root><item>v</item></root>")
      kids = doc.root.children.first.children
      expect(kids).to be_a(Moxml::NodeSet)
      expect(kids.to_a.first.name).to eq("text")
      expect(kids.to_a.first.content).to eq("v")
    end
  end
end
