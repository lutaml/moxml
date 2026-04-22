# TODO 3: EntityReference Test Coverage

## Problem

There are zero tests for EntityReference node behavior, zero tests for
entity round-trip preservation, and zero adapter-level tests for entity
reference creation or serialization. Only `EntityRegistry` has tests
(`spec/moxml/entity_registry_spec.rb`).

This means the entire EntityReference feature is untested — including the
`restore_entities` config, `create_entity_reference` factory, `visit_entity_reference`
in DocumentBuilder, and the `entity_reference` Builder DSL method.

## Required Test Coverage

### 1. EntityReference Node Tests

**File**: `spec/moxml/entity_reference_spec.rb`

```ruby
RSpec.describe Moxml::EntityReference do
  # Test per adapter (use shared examples)
  %i[nokogiri].each do |adapter|  # expand as adapters gain support
    context "with #{adapter} adapter" do
      let(:ctx) { Moxml.new(adapter) }

      it "creates an entity reference node" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("nbsp")
        expect(ref).to be_a(Moxml::EntityReference)
        expect(ref.name).to eq("nbsp")
      end

      it "has empty text content" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("amp")
        expect(ref.text).to eq("")
        expect(ref.content).to eq("")
      end

      it "serializes to entity syntax" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("mdash")
        expect(ref.to_xml).to eq("&mdash;")
      end

      it "is recognized as entity_reference type" do
        doc = ctx.create_document
        ref = doc.create_entity_reference("copy")
        expect(ref.entity_reference?).to be true
      end

      it "survives add_child and retrieval" do
        doc = ctx.create_document
        root = doc.create_element("p")
        doc.root = root
        ref = doc.create_entity_reference("nbsp")
        root.add_child(ref)
        expect(root.children.first).to be_a(Moxml::EntityReference)
        expect(root.children.first.name).to eq("nbsp")
      end

      it "validates entity reference name" do
        doc = ctx.create_document
        expect {
          doc.create_entity_reference("123invalid")
        }.to raise_error(Moxml::ValidationError)
      end
    end
  end
end
```

### 2. Builder DSL Tests

**File**: `spec/moxml/builder_spec.rb` (add to existing or create new section)

```ruby
it "creates entity references via DSL" do
  doc = Moxml::Builder.new(ctx).build do
    element("p") { entity_reference("nbsp") }
  end
  expect(doc.root.children.first).to be_a(Moxml::EntityReference)
  expect(doc.to_xml).to include("&nbsp;")
end
```

### 3. Restore Entities Integration Tests

**File**: `spec/moxml/adapter/entity_restoration_spec.rb` (shared examples)

```ruby
RSpec.shared_examples "entity restoration" do |adapter_name|
  context "with #{adapter_name}" do
    let(:ctx) { Moxml.new(adapter_name, restore_entities: true) }

    it "restores standard XML entities" do
      doc = ctx.parse("<p>a &amp; b</p>")
      output = doc.to_xml
      expect(output).to include("&amp;")
    end

    it "restores non-standard entities from registry" do
      # nbsp (U+00A0) is in the bundled W3C entity set
      doc = ctx.parse("<p>\u00A0</p>")
      output = doc.to_xml
      expect(output).to include("&nbsp;")
    end

    it "preserves entity syntax through round-trip" do
      doc = ctx.parse("<p>&nbsp;&copy;&mdash;</p>")
      output = doc.to_xml
      reparsed = ctx.parse(output)
      # Text content should be identical after round-trip
      expect(reparsed.root.text).to eq(doc.root.text)
    end

    it "does not restore entities when restore_entities is false" do
      ctx_no_restore = Moxml.new(adapter_name, restore_entities: false)
      doc = ctx_no_restore.parse("<p>a &amp; b</p>")
      output = doc.to_xml
      # Standard entities may still appear as &amp; due to XML escaping,
      # but no EntityReference nodes should be created
      expect(doc.root.children).not_to include(a_kind_of(Moxml::EntityReference))
    end
  end
end
```

### 4. Cross-Adapter Consistency Tests

**File**: `spec/consistency/entity_reference_consistency_spec.rb`

Verify that EntityReference behavior is consistent across all adapters that
support it:
- Same entity name produces same serialization
- Same text content after round-trip
- Children enumeration includes EntityReference nodes

### 5. EntityRegistry.should_restore? Tests

**File**: Add to `spec/moxml/entity_registry_spec.rb`

```ruby
describe "#should_restore?" do
  it "always restores the 5 standard XML entities" do
    registry = described_class.new
    config = Moxml::Config.new(:nokogiri)
    expect(registry.should_restore?(0x26, config: config)).to be true  # amp
    expect(registry.should_restore?(0x3C, config: config)).to be true  # lt
  end

  it "restores non-standard entities only when restore_entities is true" do
    registry = described_class.new
    config_on = Moxml::Config.new(:nokogiri)
    config_on.restore_entities = true
    config_off = Moxml::Config.new(:nokogiri)
    config_off.restore_entities = false

    expect(registry.should_restore?(0xA0, config: config_on)).to be true   # nbsp
    expect(registry.should_restore?(0xA0, config: config_off)).to be false
  end
end
```

## Dependencies

- TODO 1 must be partially complete (at least one adapter working) before
  adapter-level tests can pass
- TODO 2 must be complete before non-standard entity restoration tests can pass
