# frozen_string_literal: true

RSpec.describe Moxml::EntityRegistry do
  before do
    described_class.reset
  end

  describe ".entity_data" do
    it "loads entity data from bundled JSON" do
      data = described_class.entity_data
      expect(data).to be_a(Hash)
      expect(data.keys).to include("amp", "nbsp", "copy")
    end

    it "caches entity data" do
      data1 = described_class.entity_data
      data2 = described_class.entity_data
      expect(data1.object_id).to eq(data2.object_id)
    end
  end

  describe ".reset" do
    it "clears cached entity data" do
      data1 = described_class.entity_data
      described_class.reset
      # After reset, a new data hash is loaded
      expect(described_class.entity_data).not_to be(data1)
    end
  end

  describe "#initialize with :required mode" do
    it "loads all entities from bundled data" do
      registry = described_class.new(mode: :required)
      expect(registry.by_name.keys.length).to be > 2000
      expect(registry.declared?("nbsp")).to be true
      expect(registry.declared?("amp")).to be true
    end

    it "raises error if entity data unavailable" do
      allow(described_class).to receive(:entity_data).and_return(nil)
      expect {
        described_class.new(mode: :required)
      }.to raise_error(Moxml::EntityRegistry::EntityDataError)
    end
  end

  describe "#initialize with :disabled mode" do
    it "creates empty registry" do
      registry = described_class.new(mode: :disabled)
      expect(registry.by_name.keys).to be_empty
      expect(registry.declared?("nbsp")).to be false
    end
  end

  describe "#initialize with :optional mode" do
    it "loads entities when available" do
      registry = described_class.new(mode: :optional)
      expect(registry.by_name.keys.length).to be > 2000
      expect(registry.declared?("nbsp")).to be true
    end

    it "does not raise when entity data unavailable" do
      allow(described_class).to receive(:entity_data).and_return(nil)
      expect {
        described_class.new(mode: :optional)
      }.not_to raise_error
    end
  end

  describe "#initialize with :custom mode" do
    it "loads custom entities from provider" do
      custom_provider = -> { { "custom" => 12345, "special" => 67890 } }
      registry = described_class.new(mode: :custom, entity_provider: custom_provider)
      expect(registry.by_name.keys).to contain_exactly("custom", "special")
      expect(registry.declared?("custom")).to be true
      expect(registry.codepoint_for_name("custom")).to eq(12345)
    end

    it "works with nil provider" do
      registry = described_class.new(mode: :custom, entity_provider: nil)
      expect(registry.by_name.keys).to be_empty
    end

    it "works with provider returning nil" do
      registry = described_class.new(mode: :custom, entity_provider: -> { nil })
      expect(registry.by_name.keys).to be_empty
    end
  end

  describe "#declared?" do
    it "returns true for known entities" do
      registry = described_class.new
      expect(registry.declared?("nbsp")).to be true
      expect(registry.declared?("amp")).to be true
      expect(registry.declared?("copy")).to be true
    end

    it "returns false for unknown entities" do
      registry = described_class.new
      expect(registry.declared?("unknown_entity")).to be false
    end
  end

  describe "#codepoint_for_name" do
    it "returns Unicode codepoint for entity name" do
      registry = described_class.new
      expect(registry.codepoint_for_name("nbsp")).to eq(160)
      expect(registry.codepoint_for_name("amp")).to eq(38)
      expect(registry.codepoint_for_name("copy")).to eq(169)
    end

    it "returns nil for unknown entity" do
      registry = described_class.new
      expect(registry.codepoint_for_name("unknown")).to be_nil
    end
  end

  describe "#names_for_codepoint" do
    it "returns all entity names for a codepoint" do
      registry = described_class.new
      # nbsp has codepoint 160
      names = registry.names_for_codepoint(160)
      expect(names).to be_an(Array)
      expect(names).to include("nbsp")
    end
  end

  describe "#primary_name_for_codepoint" do
    it "returns first entity name for codepoint" do
      registry = described_class.new
      name = registry.primary_name_for_codepoint(160)
      expect(name).to be_a(String)
    end
  end

  describe "#register" do
    it "adds entities to the registry" do
      registry = described_class.new(mode: :disabled)
      registry.register({ "new_entity" => 99999 })
      expect(registry.declared?("new_entity")).to be true
      expect(registry.codepoint_for_name("new_entity")).to eq(99999)
    end

    it "allows multiple names for same codepoint" do
      registry = described_class.new(mode: :disabled)
      registry.register({ "entity_a" => 12345, "entity_b" => 12345 })
      expect(registry.names_for_codepoint(12345)).to contain_exactly("entity_a", "entity_b")
    end
  end

  describe "#clear!" do
    it "removes all entities" do
      registry = described_class.new
      expect(registry.by_name.keys).not_to be_empty
      registry.clear!
      expect(registry.by_name.keys).to be_empty
    end
  end

  describe "load_html5, load_mathml, load_iso, load_all" do
    it "load_html5 returns self for chaining" do
      registry = described_class.new
      expect(registry.load_html5).to be(registry)
    end

    it "load_mathml returns self for chaining" do
      registry = described_class.new
      expect(registry.load_mathml).to be(registry)
    end

    it "load_iso returns self for chaining" do
      registry = described_class.new
      expect(registry.load_iso).to be(registry)
    end

    it "load_all returns self for chaining" do
      registry = described_class.new
      expect(registry.load_all).to be(registry)
    end
  end
end
