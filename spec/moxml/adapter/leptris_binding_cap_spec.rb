# frozen_string_literal: true

require "spec_helper"

# 0.5.100's cap valves called .clear on the registry — an
# ObjectSpace::WeakMap in weak-wrapper mode (Ruby 3.4+) has no
# #clear, so the first parse crossing 8,192 bridges crashed with
# NoMethodError. The valve replaces the registry wholesale now.
RSpec.describe "leptris binding registry cap valve" do
  let(:ctx) { Moxml.new(:leptris) }
  let(:doc) do
    ctx.parse("<r>#{Array.new(8_300) { |i| "<e#{i}/>" }.join}</r>")
  end

  it "bridges past the cap" do
    children = doc.root.children.to_a
    expect(children.size).to be > 8_192

    bridged = children.map { |child| Moxml::Adapter::Leptris.to_binding(child.native) }
    expect(bridged.compact.size).to eq(children.size)
  end

  it "bridges stay identity-stable across the valve" do
    children = doc.root.children.to_a
    first_pass = children.map { |child| Moxml::Adapter::Leptris.to_binding(child.native) }
    second_pass = children.map { |child| Moxml::Adapter::Leptris.to_binding(child.native) }
    expect(first_pass.zip(second_pass).all? { |one, other| one.equal?(other) }).to be(true)
  end
end
