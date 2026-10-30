# frozen_string_literal: true

require "spec_helper"

# #494: the registry's extension contract, asserted mechanically —
# adding an adapter is one AVAILABLE_ADAPTERS entry plus its adapter
# file (a Base subclass per CONST_NAME_MAP) and, when the name differs
# from the engine gem, one ENGINE_GEMS declaration. This spec walks the
# registry and fails if any adapter breaks the trio, so the
# open/closed shape cannot rot.
RSpec.describe Moxml::Adapter do
  describe "extension contract" do
    it "resolves every registered adapter through the registry" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        adapter = described_class.load(name)

        expect(adapter).to be <= Moxml::Adapter::Base,
                           "#{name} is not a Base subclass"
      end
    end

    it "has an adapter file for every registered adapter" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        path = File.expand_path("../../lib/moxml/adapter/#{name}.rb", __dir__)

        expect(File).to exist(path),
                        "no adapter file at moxml/adapter/#{name}.rb"
      end
    end

    it "declares a loadable engine gem for every registered adapter" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        gem_name = described_class::ENGINE_GEMS[name] || name.to_s
        spec = Gem::Specification.find_by_name(gem_name)

        expect(spec).not_to be_nil,
                            "the #{gem_name} gem (#{name}'s engine) is not loadable"
      end
    end

    it "keeps deprecation entries within the registered set" do
      unknown = described_class::DEPRECATED_ADAPTERS.keys -
        described_class::AVAILABLE_ADAPTERS

      expect(unknown).to be_empty
    end

    it "derives platform selection from the single Opal predicate" do
      expected = if described_class.opal_runtime?
                   described_class::OPAL_AVAILABLE_ADAPTERS
                 else
                   described_class::AVAILABLE_ADAPTERS
                 end

      expect(described_class.platform_adapters).to eq(expected)
    end
  end
end
