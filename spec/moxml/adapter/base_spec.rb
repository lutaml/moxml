# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Adapter::Base do
  describe ".name" do
    it "returns adapter name" do
      expect(described_class.name).to include("Base")
    end
  end

  describe "interface methods" do
    it "defines parse method" do
      expect(described_class).to respond_to(:parse)
    end

    it "defines create_document method" do
      expect(described_class).to respond_to(:create_document)
    end

    it "defines serialize method" do
      # Base class doesn't implement serialize - each adapter does
      # This is tested in the individual adapter specs
      skip "Serialize is adapter-specific, not in Base"
    end
  end

  describe "children compatibility (issue #218)" do
    it "calls one-argument downstream overrides without the keyword" do
      legacy = Class.new(Moxml::Adapter::Nokogiri) do
        class << self
          # The override exists for its one-argument signature —
          # the pre-0.5.36 downstream shape.
          # rubocop:disable-next Lint/UselessMethodDefinition
          def children(node)
            super
          end
        end
      end
      expect(legacy.children_accepts_entity_flag?).to be(false)
      node = Moxml.new(:nokogiri).parse(%(<r><e>x</e></r>)).root.native
      expect(legacy.children(node).length).to eq(1)
    end

    it "passes the keyword to built-in adapters" do
      expect(Moxml::Adapter::Leptris.children_accepts_entity_flag?).to be(true)
      expect(Moxml::Adapter::Nokogiri.children_accepts_entity_flag?).to be(true)
    end

    it "assumes the keyword when Method#parameters returns no data" do
      # Opal without arity checking answers a bare JS undefined for
      # parameters — not even nil?. Exercise the decision through the
      # real values the probe can see.
      probe = described_class.children_params_flag(nil)
      expect(probe).to be(true)
      expect(described_class.children_params_flag([%i[req node]])).to be(false)
      expect(
        described_class.children_params_flag(
          [%i[req node], %i[key entity_bearing]],
        ),
      ).to be(true)
    end
  end
end
