# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Adapter, ".platform_adapters" do
  it "includes all known adapters under MRI" do
    expect(described_class.platform_adapters).to include(:nokogiri, :oga,
                                                         :rexml, :ox)
  end

  it "uses the AVAILABLE_ADAPTERS constant under MRI" do
    expect(described_class.platform_adapters).to eq(Moxml::Adapter::AVAILABLE_ADAPTERS)
  end
end

RSpec.describe Moxml::Adapter, ".available?" do
  it "returns true for :oga" do
    expect(described_class.available?(:oga)).to be true
  end

  it "returns true for :nokogiri under MRI" do
    expect(described_class.available?(:nokogiri)).to be true
  end

  context "when Opal platform adapters are in effect" do
    before do
      allow(described_class).to receive(:platform_adapters)
        .and_return(Moxml::Adapter::OPAL_AVAILABLE_ADAPTERS)
    end

    it "returns false for :nokogiri" do
      expect(described_class.available?(:nokogiri)).to be false
    end

    it "returns true for :rexml" do
      expect(described_class.available?(:rexml)).to be true
    end
  end
end

RSpec.describe Moxml::Adapter, ".load" do
  context "when Opal platform adapters are in effect" do
    before do
      allow(described_class).to receive(:platform_adapters)
        .and_return(Moxml::Adapter::OPAL_AVAILABLE_ADAPTERS)
    end

    it "raises AdapterError for :nokogiri" do
      expect { described_class.load(:nokogiri) }.to raise_error(
        Moxml::AdapterError, /not available on this platform/
      )
    end
  end
end

RSpec.describe "Moxml::Adapter::OPAL_AVAILABLE_ADAPTERS" do
  it "contains only :rexml" do
    expect(Moxml::Adapter::OPAL_AVAILABLE_ADAPTERS).to eq(%i[rexml])
  end
end

RSpec.describe "Moxml::Adapter::CONST_NAME_MAP" do
  it "maps :headed_ox to HeadedOx" do
    expect(Moxml::Adapter::CONST_NAME_MAP[:headed_ox]).to eq("HeadedOx")
  end

  it "falls back to capitalize for unmapped adapters" do
    expect(Moxml::Adapter::CONST_NAME_MAP[:nokogiri]).to be_nil
  end
end
