# frozen_string_literal: true

require "spec_helper"

# Element#add_element adapter-contract conformance (#312): the
# child must land attached with ALL attributes in one call —
# through the bulk face (leptris) or the portable create_element +
# add_child fallback (every other adapter). Guards both halves of
# the contract: a missing base default NoMethodErrors on non-face
# adapters, a broken fallback loses attributes or the attach.
RSpec.describe Moxml::Element do
  ADAPTERS = %i[leptris nokogiri ox oga rexml libxml].freeze # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  def with_adapter(name)
    ctx = Moxml.new(name)
    yield ctx
  rescue StandardError, LoadError
    skip "adapter #{name} unavailable"
  end

  it "attaches a child with all attributes on every available adapter" do
    ADAPTERS.each do |name|
      with_adapter(name) do |ctx|
        doc = ctx.parse("<catalog/>")
        root = doc.root
        child = root.add_element("record", "id" => "r1", "kind" => "k1")

        expect(child.name).to eq("record"), "#{name}: name"
        expect(child["id"]).to eq("r1"), "#{name}: id attr"
        expect(child["kind"]).to eq("k1"), "#{name}: kind attr"
        expect(child.parent.name).to eq("catalog"), "#{name}: attach"
        expect(root.children.map(&:name)).to include("record"), "#{name}: visible in children"
      end
    end
  end

  it "nests under a non-root element with empty attrs" do
    ADAPTERS.each do |name|
      with_adapter(name) do |ctx|
        doc = ctx.parse("<catalog><record/></catalog>")
        record = doc.root.children.first
        field = record.add_element("field")

        expect(field.name).to eq("field"), "#{name}: name"
        expect(field.attributes).to be_empty, "#{name}: no attrs"
        expect(field.parent.name).to eq("record"), "#{name}: attach"
      end
    end
  end
end
