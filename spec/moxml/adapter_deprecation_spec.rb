# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::Adapter do
  describe ".warn_deprecated!" do
    # The once-per-process state is module-level; isolate each
    # example from prior loads and from later suites.
    around do |example|
      described_class.instance_variable_set(:@deprecation_warned, {})
      example.run
      described_class.instance_variable_set(:@deprecation_warned, {})
    end

    it "warns once per deprecated adapter per process" do
      expect do
        Moxml.new(:headed_ox)
      end.to output(%r{:headed_ox adapter is deprecated}).to_stderr
      expect do
        Moxml.new(:headed_ox)
      end.not_to output.to_stderr
    end

    it "guides every deprecated adapter toward the governed matrix" do
      described_class::DEPRECATED_ADAPTERS.each_value do |guidance|
        expect(guidance).to match(/:nokogiri|:leptris/)
      end
    end

    it "does not warn for the governed matrix" do
      expect do
        Moxml.new(:leptris)
        Moxml.new(:nokogiri)
      end.not_to output(/deprecated/).to_stderr
    end

    it "does not warn for unknown names" do
      expect do
        described_class.warn_deprecated!(:definitely_not_an_adapter)
      end.not_to output.to_stderr
    end

    it "keeps the deprecated adapters loadable through the cycle" do
      described_class::DEPRECATED_ADAPTERS.each_key do |name|
        expect(described_class.available?(name)).to be(true)
      end
    end
  end
end
