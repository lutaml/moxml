# frozen_string_literal: true

RSpec.shared_examples "Moxml::EntityReference" do
  let(:context) { Moxml.new }

  describe "entity reference node" do
    let(:doc) { context.create_document }

    before do
      root = doc.create_element("root")
      doc.add_child(root)
    end

    describe "creation" do
      it "creates an entity reference node" do
        ref = doc.create_entity_reference("nbsp")
        expect(ref).to be_a(Moxml::EntityReference)
      end

      it "has empty text content" do
        ref = doc.create_entity_reference("amp")
        expect(ref.text).to eq("")
        expect(ref.content).to eq("")
      end

      it "exposes entity name" do
        ref = doc.create_entity_reference("mdash")
        expect(ref.name).to eq("mdash")
      end

      it "is recognized as entity_reference type" do
        ref = doc.create_entity_reference("copy")
        expect(ref.entity_reference?).to be true
        expect(ref).not_to be_element
        expect(ref).not_to be_text
      end

      it "validates entity reference name" do
        expect { doc.create_entity_reference("123invalid") }.to raise_error(Moxml::ValidationError)
      end
    end

    describe "serialization" do
      it "serializes to entity syntax" do
        ref = doc.create_entity_reference("nbsp")
        expect(ref.to_xml).to eq("&nbsp;")
      end

      it "serializes standard XML entities" do
        ref = doc.create_entity_reference("amp")
        expect(ref.to_xml).to eq("&amp;")
      end
    end

    describe "tree integration" do
      it "survives add_child and retrieval" do
        root = doc.root
        ref = doc.create_entity_reference("nbsp")
        root.add_child(ref)
        children = root.children
        expect(children.size).to be >= 1
        first = children.last
        expect(first).to be_a(Moxml::EntityReference)
        expect(first.name).to eq("nbsp")
      end

      it "serializes within element content" do
        root = doc.root
        root.add_child(doc.create_text("before"))
        root.add_child(doc.create_entity_reference("nbsp"))
        root.add_child(doc.create_text("after"))
        xml = doc.to_xml
        expect(xml).to include("&nbsp;")
        expect(xml).to include("before")
        expect(xml).to include("after")
      end

      it "supports multiple entity references" do
        root = doc.root
        root.add_child(doc.create_entity_reference("nbsp"))
        root.add_child(doc.create_entity_reference("copy"))
        root.add_child(doc.create_entity_reference("mdash"))
        xml = doc.to_xml
        expect(xml).to include("&nbsp;")
        expect(xml).to include("&copy;")
        expect(xml).to include("&mdash;")
      end
    end

    describe "equality" do
      it "has the same name as another entity reference with same name" do
        ref1 = doc.create_entity_reference("amp")
        ref2 = doc.create_entity_reference("amp")
        expect(ref1.name).to eq(ref2.name)
      end

      it "does not equal entity reference with different name" do
        ref1 = doc.create_entity_reference("amp")
        ref2 = doc.create_entity_reference("nbsp")
        expect(ref1.name).not_to eq(ref2.name)
      end
    end
  end

  describe "entity reference via builder DSL" do
    it "creates entity references" do
      built = Moxml::Builder.new(context).build do
        element("p") { entity_reference("nbsp") }
      end
      expect(built.root.children.last).to be_a(Moxml::EntityReference)
      expect(built.root.children.last.name).to eq("nbsp")
      expect(built.to_xml).to include("&nbsp;")
    end

    it "mixes text and entity references" do
      built = Moxml::Builder.new(context).build do
        element("p") do
          text "Copyright"
          entity_reference("copy")
          text " 2024"
        end
      end
      xml = built.to_xml
      expect(xml).to include("Copyright")
      expect(xml).to include("&copy;")
      expect(xml).to include("2024")
    end
  end

  describe "entity restoration" do
    it "restores standard XML entities when enabled" do
      ctx_restore = Moxml.new(context.config.adapter_name) { |c| c.restore_entities = true }
      doc = ctx_restore.parse("<p>a&amp;b</p>")
      output = doc.to_xml
      expect(output).to include("&amp;")
    end

    it "does not create entity references when disabled" do
      ctx_no_restore = Moxml.new(context.config.adapter_name) { |c| c.restore_entities = false }
      doc = ctx_no_restore.parse("<p>text</p>")
      refs = doc.root.children.select { |c| c.is_a?(Moxml::EntityReference) }
      expect(refs).to be_empty
    end
  end

  describe "EntityRegistry#should_restore?" do
    let(:registry) { context.entity_registry }

    let(:config_on) do
      cfg = Moxml::Config.new(context.config.adapter_name)
      cfg.restore_entities = true
      cfg
    end

    let(:config_off) do
      cfg = Moxml::Config.new(context.config.adapter_name)
      cfg.restore_entities = false
      cfg
    end

    it "always restores the 5 standard XML entities" do
      expect(registry.should_restore?(0x26, config: config_on)).to be true   # amp
      expect(registry.should_restore?(0x3C, config: config_on)).to be true   # lt
      expect(registry.should_restore?(0x3E, config: config_on)).to be true   # gt
      expect(registry.should_restore?(0x22, config: config_on)).to be true   # quot
      expect(registry.should_restore?(0x27, config: config_on)).to be true   # apos
    end

    it "restores standard XML entities even when restore_entities is false" do
      expect(registry.should_restore?(0x26, config: config_off)).to be true  # amp
      expect(registry.should_restore?(0x3C, config: config_off)).to be true  # lt
    end

    it "restores non-standard entities only when restore_entities is true" do
      expect(registry.should_restore?(0xA0, config: config_on)).to be true   # nbsp
      expect(registry.should_restore?(0xA0, config: config_off)).to be false
    end

    it "does not restore unknown codepoints" do
      expect(registry.should_restore?(0xDEAD, config: config_on)).to be false
    end
  end
end
