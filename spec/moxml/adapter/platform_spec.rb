# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Adapter do
  describe ".platform_adapters" do
    it "includes all known adapters under MRI" do
      expect(described_class.platform_adapters).to include(:nokogiri, :oga,
                                                           :rexml, :ox)
    end

    it "uses the AVAILABLE_ADAPTERS constant" do
      expect(described_class.platform_adapters).to eq(Moxml::Adapter::AVAILABLE_ADAPTERS)
    end
  end

  describe ".available?" do
    it "returns true for :oga" do
      expect(described_class.available?(:oga)).to be true
    end

    it "returns true for :nokogiri" do
      expect(described_class.available?(:nokogiri)).to be true
    end
  end

  describe "CONST_NAME_MAP" do
    it "maps :headed_ox to HeadedOx" do
      expect(Moxml::Adapter::CONST_NAME_MAP[:headed_ox]).to eq("HeadedOx")
    end

    it "falls back to capitalize for unmapped adapters" do
      expect(Moxml::Adapter::CONST_NAME_MAP[:nokogiri]).to be_nil
    end
  end

  describe "default adapter / available list invariants" do
    it "PREFERRED and FALLBACK adapters are members of AVAILABLE_ADAPTERS" do
      expect(Moxml::Adapter::AVAILABLE_ADAPTERS)
        .to include(Moxml::Config::PREFERRED_ADAPTER, Moxml::Config::FALLBACK_ADAPTER)
    end

    it "the resolved runtime default adapter is loadable" do
      expect(Moxml::Adapter::AVAILABLE_ADAPTERS)
        .to include(Moxml::Config.default_adapter)
    end

    it "prefers leptris only when the installed binding meets the floor" do
      if Moxml::Config.leptris_preferred_available?
        expect(Moxml::Config.runtime_default_adapter).to eq(:leptris)
      else
        expect(Moxml::Config.runtime_default_adapter).not_to eq(:leptris)
      end
    end

    it "pins the leptris binding floor at 1.9.386.0 (raised 2026-09-20, raised again 2026-10-30; enforced at load)" do
      skip "leptris not installed" unless described_class.available?(:leptris)

      adapter = described_class.load(:leptris)
      expect(adapter::MINIMUM_BINDING_VERSION).to eq("1.9.386.0")
      expect(Gem::Version.new(Leptris::VERSION))
        .to be >= Gem::Version.new(adapter::MINIMUM_BINDING_VERSION)
    end
  end
end
