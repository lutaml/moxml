# frozen_string_literal: true

require "spec_helper"

# leptris-ruby#629 — registering SUBCLASSES as wrapper klasses made
# XPath answer zero rows: wrap_binding_node resolved the node kind
# through the exact-class hash (IDENTITY_WALK_TYPE), so a subclass
# minted nil there and every walk-yielded node dropped from results.
# #340's register_wrapper_klasses admits ANY NativeNode subclass and
# consumers register their own (define_hot_readers subclasses,
# leptris-ruby#627) — the resolution must be subclass-aware.
RSpec.describe "leptris registered-subclass wraps" do
  let(:ctx) { Moxml.new(:leptris) }

  before do
    unless
        defined?(Leptris::XML::Native.define_hot_readers) &&
            ctx.parse("<r/>").native
                .instance_variable_get(:@doc_klass_map)
      skip "binding lacks the C-mint registered-klass face"
    end
  end

  def parse_with_map(map)
    ctx.parse('<root xmlns="urn:a"><child xmlns="urn:b"><leaf xmlns=""/></child></root>')
      .tap do |doc|
        doc.native.instance_variable_set(:@doc_klass_map, map) if map
      end
  end

  it "matches with the exact classes the adapter registered" do
    doc = parse_with_map(nil) # the adapter registers at parse
    expect(doc.at_xpath("//xmlns:leaf", "xmlns" => "")&.name).to eq("leaf")
  end

  it "matches with a plain Class.new of the registered element klass" do
    doc = ctx.parse('<root xmlns="urn:a"><child xmlns="urn:b"><leaf xmlns=""/></child></root>')
    orig = doc.native.instance_variable_get(:@doc_klass_map)
    map = [Class.new(orig[0]), orig[1], orig[2], orig[3], orig[4]]
    doc.native.instance_variable_set(:@doc_klass_map, map)
    expect(doc.at_xpath("//xmlns:leaf", "xmlns" => "")&.name).to eq("leaf")
  end

  it "matches with a define_hot_readers subclass registered" do
    doc = ctx.parse('<root xmlns="urn:a"><child xmlns="urn:b"><leaf xmlns=""/></child></root>')
    orig = doc.native.instance_variable_get(:@doc_klass_map)
    hot = Class.new(orig[0]) do
      Leptris::XML::Native.define_hot_readers(self)
    end
    doc.native.instance_variable_set(:@doc_klass_map,
                                     [hot, orig[1], orig[2], orig[3], orig[4]])
    row = doc.at_xpath("//xmlns:leaf", "xmlns" => "")
    expect(row&.name).to eq("leaf")
    expect(row).to be_a(hot) # the consumer's klass mints on walks
  end

  it "matches with a subclass of every kind registered" do
    doc = ctx.parse('<root xmlns="urn:a"><child xmlns="urn:b"><leaf xmlns=""/></child></root>')
    orig = doc.native.instance_variable_get(:@doc_klass_map)
    map = orig.map { |k| k.is_a?(Class) ? Class.new(k) : k }
    doc.native.instance_variable_set(:@doc_klass_map, map)
    expect(doc.at_xpath("//xmlns:leaf", "xmlns" => "")&.name).to eq("leaf")
  end

  it "keeps the mint klass through the walk (contract rides the subclass)" do
    doc = ctx.parse('<root xmlns="urn:a"><child xmlns="urn:b"><leaf xmlns=""/></child></root>')
    orig = doc.native.instance_variable_get(:@doc_klass_map)
    map = orig.map { |k| k.is_a?(Class) ? Class.new(k) : k }
    doc.native.instance_variable_set(:@doc_klass_map, map)
    row = doc.at_xpath("//xmlns:leaf", "xmlns" => "")
    expect(row.class).to eq(map[0])
    expect(row).to be_a(Moxml::Node) # the contract still rides
  end
end
