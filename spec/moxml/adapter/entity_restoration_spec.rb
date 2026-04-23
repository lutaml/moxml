# frozen_string_literal: true

require "spec_helper"

# Adapters that use DocumentBuilder for parse (entity restoration during parsing works)
DBUILD_ADAPTERS = %i[oga rexml].freeze

# All adapters with entity reference support
ENTITY_ADAPTERS = %i[nokogiri oga ox rexml].freeze

RSpec.shared_examples "standard entity preservation" do |adapter_name|
  context "with #{adapter_name}", adapter: adapter_name do
    it "preserves amp entity through round-trip" do
      ctx = Moxml.new(adapter_name) { |c| c.restore_entities = true }
      doc = ctx.parse("<p>a &amp; b</p>")
      expect(doc.to_xml).to include("&amp;")
    end

    it "preserves lt entity through round-trip" do
      ctx = Moxml.new(adapter_name) { |c| c.restore_entities = true }
      doc = ctx.parse("<p>a &lt; b</p>")
      expect(doc.to_xml).to include("&lt;")
    end

    it "preserves gt entity through round-trip" do
      ctx = Moxml.new(adapter_name) { |c| c.restore_entities = true }
      doc = ctx.parse("<p>a &gt; b</p>")
      expect(doc.to_xml).to include("&gt;")
    end

    it "produces valid XML through round-trip" do
      ctx = Moxml.new(adapter_name) { |c| c.restore_entities = true }
      doc = ctx.parse("<p>&amp; text &amp;</p>")
      output = doc.to_xml
      expect { ctx.parse(output) }.not_to raise_error
    end
  end
end

RSpec.shared_examples "non-standard entity restoration via DocumentBuilder" do |adapter_name|
  context "with #{adapter_name}", adapter: adapter_name do
    let(:ctx) { Moxml.new(adapter_name) { |c| c.restore_entities = true } }

    it "restores nbsp (U+00A0) from bundled W3C entity set" do
      doc = ctx.parse("<p>\u00A0</p>")
      expect(doc.to_xml).to include("&nbsp;")
    end

    it "restores copy (U+00A9) from bundled W3C entity set" do
      doc = ctx.parse("<p>\u00A9</p>")
      expect(doc.to_xml).to include("&copy;")
    end

    it "restores mdash (U+2014) from bundled W3C entity set" do
      doc = ctx.parse("<p>\u2014</p>")
      expect(doc.to_xml).to include("&mdash;")
    end

    it "restores multiple entities in a single text node" do
      doc = ctx.parse("<p>before\u00A0middle\u00A9end</p>")
      output = doc.to_xml
      expect(output).to include("&nbsp;")
      expect(output).to include("&copy;")
    end
  end
end

RSpec.shared_examples "restore_entities disabled" do |adapter_name|
  context "with #{adapter_name}", adapter: adapter_name do
    let(:ctx) { Moxml.new(adapter_name) { |c| c.restore_entities = false } }

    it "does not create EntityReference nodes for standard entities" do
      doc = ctx.parse("<p>a &amp; b</p>")
      entity_children = doc.root.children.grep(Moxml::EntityReference)
      expect(entity_children).to be_empty
    end

    it "does not create EntityReference nodes for non-standard characters" do
      doc = ctx.parse("<p>\u00A0</p>")
      entity_children = doc.root.children.grep(Moxml::EntityReference)
      expect(entity_children).to be_empty
    end
  end
end

RSpec.describe "Entity restoration" do
  ENTITY_ADAPTERS.each do |adapter_name|
    it_behaves_like "standard entity preservation", adapter_name
  end

  DBUILD_ADAPTERS.each do |adapter_name|
    it_behaves_like "non-standard entity restoration via DocumentBuilder",
                    adapter_name

    it_behaves_like "restore_entities disabled", adapter_name
  end
end
