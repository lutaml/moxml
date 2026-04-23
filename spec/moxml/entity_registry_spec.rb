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
      expect do
        described_class.new(mode: :required)
      end.to raise_error(Moxml::EntityRegistry::EntityDataError)
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
      expect do
        described_class.new(mode: :optional)
      end.not_to raise_error
    end
  end

  describe "#initialize with :custom mode" do
    it "loads custom entities from provider" do
      custom_provider = -> { { "custom" => 12345, "special" => 67890 } }
      registry = described_class.new(mode: :custom,
                                     entity_provider: custom_provider)
      expect(registry.by_name.keys).to contain_exactly("custom", "special")
      expect(registry.declared?("custom")).to be true
      expect(registry.codepoint_for_name("custom")).to eq(12345)
    end

    it "works with nil provider" do
      registry = described_class.new(mode: :custom, entity_provider: nil)
      expect(registry.by_name.keys).to be_empty
    end

    it "works with provider returning nil" do
      registry = described_class.new(mode: :custom, entity_provider: -> {})
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
      expect(registry.names_for_codepoint(12345)).to contain_exactly(
        "entity_a", "entity_b"
      )
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

  describe "#standard_entity?" do
    it "returns true for the 5 standard XML entities" do
      registry = described_class.new
      expect(registry.standard_entity?(0x26)).to be true  # amp
      expect(registry.standard_entity?(0x3C)).to be true  # lt
      expect(registry.standard_entity?(0x3E)).to be true  # gt
      expect(registry.standard_entity?(0x22)).to be true  # quot
      expect(registry.standard_entity?(0x27)).to be true  # apos
    end

    it "returns false for non-standard codepoints" do
      registry = described_class.new
      expect(registry.standard_entity?(0xA0)).to be false   # nbsp
      expect(registry.standard_entity?(0xA9)).to be false   # copy
      expect(registry.standard_entity?(0x30)).to be false   # '0'
    end
  end

  describe "#should_restore?" do
    it "always restores the 5 standard XML entities regardless of config" do
      registry = described_class.new
      config = Moxml::Config.new(:nokogiri)
      config.restore_entities = false
      expect(registry.should_restore?(0x26, config: config)).to be true  # amp
      expect(registry.should_restore?(0x3C, config: config)).to be true  # lt
    end

    it "restores non-standard entities when restore_entities is true and mode is lenient" do
      registry = described_class.new
      config = Moxml::Config.new(:nokogiri)
      config.restore_entities = true
      config.entity_restoration_mode = :lenient
      expect(registry.should_restore?(0xA0, config: config)).to be true  # nbsp
      expect(registry.should_restore?(0xA9, config: config)).to be true  # copy
    end

    it "does not restore non-standard entities when restore_entities is false" do
      registry = described_class.new
      config = Moxml::Config.new(:nokogiri)
      config.restore_entities = false
      expect(registry.should_restore?(0xA0, config: config)).to be false
    end

    it "returns false for codepoints not in the registry" do
      registry = described_class.new(mode: :disabled)
      config = Moxml::Config.new(:nokogiri)
      config.restore_entities = true
      expect(registry.should_restore?(0x30, config: config)).to be false # '0'
    end
  end

  describe "#restorable_codepoints" do
    it "returns the set of codepoints that could be restored" do
      registry = described_class.new
      codepoints = registry.restorable_codepoints
      expect(codepoints).to be_a(Set)
      expect(codepoints).to include(0x26)  # amp
      expect(codepoints).to include(0xA0)  # nbsp
      expect(codepoints.size).to be > 100
    end

    it "returns only standard codepoints for empty registry" do
      registry = described_class.new(mode: :disabled)
      codepoints = registry.restorable_codepoints
      expect(codepoints).to eq(described_class::STANDARD_CODEPOINTS)
    end
  end
end
