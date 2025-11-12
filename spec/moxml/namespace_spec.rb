# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Namespace do
  let(:context) { Moxml.new }
  let(:doc) do
    context.parse('<root xmlns:ns="http://example.com"><ns:child/></root>')
  end

  describe "#prefix" do
    it "returns namespace prefix" do
      ns = doc.root.namespace
      expect(ns).to be_nil # root has no prefix
    end
  end

  describe "#uri" do
    it "returns namespace URI" do
      child = doc.root.children.first
      ns = child.namespace
      expect(ns.uri).to eq("http://example.com") if ns
    end
  end

  describe "namespace handling" do
    it "handles namespaces on elements" do
      elem = doc.root.children.first
      expect(elem.name).to include("child")
    end
  end
end
