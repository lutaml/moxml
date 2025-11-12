# frozen_string_literal: true

# spec/moxml_spec.rb
RSpec.describe Moxml do
  it "has a version number" do
    expect(Moxml::VERSION).not_to be_nil
  end

  describe ".new" do
    it "creates a new context" do
      expect(described_class.new).to be_a(Moxml::Context)
    end

    it "accepts adapter specification" do
      context = described_class.new(:nokogiri)
      expect(context.config.adapter_name).to eq(:nokogiri)
    end

    it "raises error for invalid adapter" do
      expect { described_class.new(:invalid) }.to raise_error(Moxml::AdapterError)
    end
  end

  describe ".configure" do
    around do |example|
      # preserve the original config because it may be changed in examples
      described_class.with_config { example.run }
    end

    it "sets default values without a block" do
      described_class.configure

      context = described_class.new
      expect(context.config.adapter_name).to eq(:nokogiri)
    end

    it "uses configured options from the block" do
      described_class.configure do |config|
        config.default_adapter = :oga
        config.strict_parsing = false
        config.default_encoding = "US-ASCII"
      end

      context = described_class.new
      expect(context.config.adapter_name).to eq(:oga)
      expect(context.config.strict_parsing).to be(false)
      expect(context.config.default_encoding).to eq("US-ASCII")
    end
  end
end
