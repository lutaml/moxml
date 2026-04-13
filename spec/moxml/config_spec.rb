# frozen_string_literal: true

# spec/moxml/config_spec.rb
RSpec.describe Moxml::Config do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "sets default values" do
      expect(config.adapter_name).to eq(:nokogiri)
      expect(config.strict_parsing).to be true
      expect(config.default_encoding).to eq("UTF-8")
      expect(config.default_indent).to eq(2)
      expect(config.entity_encoding).to eq(:basic)
    end

    it "sets default entity_load_mode to :required" do
      expect(config.entity_load_mode).to eq(:required)
    end

    it "sets default namespace_uri_mode to :strict" do
      expect(config.namespace_uri_mode).to eq(:strict)
    end
  end

  describe "#entity_load_mode=" do
    it "accepts valid modes" do
      %i[required optional disabled custom].each do |mode|
        config.entity_load_mode = mode
        expect(config.entity_load_mode).to eq(mode)
      end
    end

    it "raises error for invalid mode" do
      expect do
        config.entity_load_mode = :invalid
      end.to raise_error(ArgumentError)
    end
  end

  describe "#load_external_entities=" do
    it "maps true to :required" do
      config.load_external_entities = true
      expect(config.entity_load_mode).to eq(:required)
    end

    it "maps false to :disabled" do
      config.load_external_entities = false
      expect(config.entity_load_mode).to eq(:disabled)
    end

    it "accepts symbol values" do
      config.load_external_entities = :optional
      expect(config.entity_load_mode).to eq(:optional)
    end
  end

  describe "#load_external_entities" do
    it "returns true when mode is :required" do
      config.entity_load_mode = :required
      expect(config.load_external_entities).to be true
    end

    it "returns false when mode is not :required" do
      config.entity_load_mode = :disabled
      expect(config.load_external_entities).to be false
    end
  end

  describe "#namespace_uri_mode=" do
    it "accepts :strict" do
      config.namespace_uri_mode = :strict
      expect(config.namespace_uri_mode).to eq(:strict)
    end

    it "accepts :lenient" do
      config.namespace_uri_mode = :lenient
      expect(config.namespace_uri_mode).to eq(:lenient)
    end

    it "accepts string values" do
      config.namespace_uri_mode = "lenient"
      expect(config.namespace_uri_mode).to eq(:lenient)
    end

    it "raises error for invalid mode" do
      expect do
        config.namespace_uri_mode = :invalid
      end.to raise_error(ArgumentError, /Invalid namespace_uri_mode/)
    end
  end

  describe "#adapter=" do
    it "sets valid adapter" do
      config.adapter = :ox
      expect(config.adapter_name).to eq(:ox)
    end

    it "raises error for invalid adapter" do
      expect { config.adapter = :invalid }.to raise_error(Moxml::AdapterError)
    end

    it "requires adapter gem" do
      expect { config.adapter = :oga }.not_to raise_error

      expect(defined?(Oga)).to be_truthy
    end

    it "handles missing gems" do
      allow(Moxml::Adapter).to receive(:require).and_raise(LoadError)
      expect { config.adapter = :nokogiri }.to raise_error(Moxml::AdapterError)
    end
  end

  describe "#adapter" do
    it "returns nokogiri adapter by default" do
      expect(config.adapter).to eq(Moxml::Adapter::Nokogiri)
    end

    it "caches adapter instance" do
      adapter = config.adapter
      expect(config.adapter.object_id).to eq(adapter.object_id)
    end

    it "resets cached adapter when changing adapter type" do
      original = config.adapter
      config.adapter = :ox
      expect(config.adapter).not_to eq(original)
    end
  end
end
