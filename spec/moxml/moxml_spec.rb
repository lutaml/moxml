# frozen_string_literal: true

# spec/moxml_spec.rb
RSpec.describe Moxml do
  around do |example|
    original_default = Moxml::Config.instance_variable_get(:@default)
    original_default_adapter = Moxml::Config.instance_variable_get(:@default_adapter)

    Moxml::Config.remove_instance_variable(:@default) if Moxml::Config.instance_variable_defined?(:@default)
    Moxml::Config.remove_instance_variable(:@default_adapter) if Moxml::Config.instance_variable_defined?(:@default_adapter)

    example.run
  ensure
    if original_default.nil?
      Moxml::Config.remove_instance_variable(:@default) if Moxml::Config.instance_variable_defined?(:@default)
    else
      Moxml::Config.instance_variable_set(:@default, original_default)
    end

    if original_default_adapter.nil?
      Moxml::Config.remove_instance_variable(:@default_adapter) if Moxml::Config.instance_variable_defined?(:@default_adapter)
    else
      Moxml::Config.instance_variable_set(:@default_adapter, original_default_adapter)
    end
  end

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

    it "defaults to oga on Opal" do
      stub_const("RUBY_ENGINE", "opal")

      context = described_class.new
      expect(context.config.adapter_name).to eq(:oga)
    end

    it "prefers ox when it is already loaded" do
      allow(Object).to receive(:const_defined?).and_call_original
      allow(Object).to receive(:const_defined?).with(:Nokogiri).and_return(false)
      allow(Object).to receive(:const_defined?).with(:Ox).and_return(true)
      allow(Object).to receive(:const_defined?).with(:Oga).and_return(false)

      context = described_class.new
      expect(context.config.adapter_name).to eq(:ox)
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
