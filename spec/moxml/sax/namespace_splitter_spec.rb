# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::SAX::NamespaceSplitter do
  let(:bridge_class) do
    Class.new do
      include Moxml::SAX::NamespaceSplitter

      attr_reader :last_attrs, :last_ns

      def split(attributes)
        @last_attrs, @last_ns = split_attributes_and_namespaces(attributes)
      end
    end
  end

  let(:splitter) { bridge_class.new }

  describe "#split_attributes_and_namespaces" do
    it "splits hash attributes into attrs and namespaces" do
      attrs, ns = splitter.split({
                                   "xmlns" => "http://default.ns",
                                   "xmlns:foo" => "http://foo.ns",
                                   "id" => "123",
                                   "class" => "bar",
                                 })

      expect(attrs).to eq("id" => "123", "class" => "bar")
      expect(ns).to eq(nil => "http://default.ns", "foo" => "http://foo.ns")
    end

    it "splits array-of-pairs attributes" do
      attrs, ns = splitter.split([
                                   ["xmlns:prefix", "http://example.com"],
                                   ["name", "value"],
                                 ])

      expect(attrs).to eq("name" => "value")
      expect(ns).to eq("prefix" => "http://example.com")
    end

    it "returns empty hashes when all attributes are namespaces" do
      attrs, ns = splitter.split({ "xmlns" => "http://default.ns" })
      expect(attrs).to be_empty
      expect(ns).to eq(nil => "http://default.ns")
    end

    it "returns empty hashes when there are no namespaces" do
      attrs, ns = splitter.split({ "id" => "1", "name" => "test" })
      expect(attrs).to eq("id" => "1", "name" => "test")
      expect(ns).to be_empty
    end

    it "handles nil attributes" do
      attrs, ns = splitter.split(nil)
      expect(attrs).to be_empty
      expect(ns).to be_empty
    end

    it "handles empty hash" do
      attrs, ns = splitter.split({})
      expect(attrs).to be_empty
      expect(ns).to be_empty
    end
  end
end
