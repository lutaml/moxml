# frozen_string_literal: true

require "spec_helper"

# The registry's extension contract (#494): adding an adapter is the
# documented trio — one AVAILABLE_ADAPTERS entry, one requireable
# adapter file, one Base subclass. The dispatch is open for extension:
# this spec walks the registry mechanically so a new adapter that
# skips any leg fails here, not in a consumer.
RSpec.describe "Adapter registry extension contract" do
  it "loads every registered adapter through the public face" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
      adapter = Moxml::Adapter.load(name)
      expect(adapter).not_to be_nil
    end
  end

  it "resolves every registered adapter to an Adapter::Base subclass" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
      adapter = Moxml::Adapter.load(name)
      expect(adapter).to be <= Moxml::Adapter::Base
    end
  end

  it "answers available? truthfully for every registered adapter" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
      expect(Moxml::Adapter.available?(name)).to be(true)
    end
  end

  it "rejects unregistered names before any require runs" do
    expect do
      Moxml::Adapter.load(:definitely_not_an_adapter)
    end.to raise_error(Moxml::AdapterError, /not available on this platform/)
  end

  it "keeps the deprecated adapters inside the registry with guidance" do
    described = Moxml::Adapter::DEPRECATED_ADAPTERS
    expect(described.keys).to all(satisfy { |name| Moxml::Adapter::AVAILABLE_ADAPTERS.include?(name) })
    described.each_value do |guidance|
      expect(guidance).to match(/:nokogiri|:leptris/)
    end
  end
end
