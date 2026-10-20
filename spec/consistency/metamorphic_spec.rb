# frozen_string_literal: true

require "spec_helper"
require "support/xml_generator"

# Metamorphic conformance (TODO.sota/02): properties over GENERATED
# documents — no expected outputs needed, only relations that must
# hold for every input. Seeded: a failing seed reproduces locally.
# Nightly legs sweep larger seeds (SOTA_FUZZ_SEEDS).
RSpec.describe "metamorphic relations over generated documents" do
  SEEDS = (ENV.key?("SOTA_FUZZ_SEEDS") ? ENV.fetch("SOTA_FUZZ_SEEDS").split(",").map(&:to_i) : [1, 2, 3]) # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  DOCS_PER_SEED = 10 # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  def adapters
    Moxml::Adapter::AVAILABLE_ADAPTERS - [:headed_ox]
  end

  def docs
    @docs ||= SEEDS.flat_map do |seed|
      (0...DOCS_PER_SEED).map do |i|
        [:"#{seed}_#{i}", XmlGenerator.generate((seed * 1000) + i)]
      end
    end
  end

  def snapshot_structure(doc)
    doc.xpath("//*").to_a.map(&:name)
  end

  def element_attr_set(doc)
    doc.xpath("//*").to_a.map do |n|
      n.attribute_pairs.map { |k, v| [k, v] }.sort
    end
  end

  # M1: parse∘serialize identity on the information set
  it "M1 round-trips every generated document on every adapter" do
    docs.each do |seed_tag, xml|
      adapters.each do |name|
        begin
          ctx = Moxml.new(name)
          doc = ctx.parse(xml)
        rescue Moxml::Error, NotImplementedError, LoadError
          next
        end
        first = snapshot_structure(doc)
        again = ctx.parse(doc.to_xml(indent: 0))
        expect(snapshot_structure(again)).to eq(first),
                                             "M1 drift #{seed_tag}/#{name}"
      end
    end
  end

  # M2: canonicalization idempotence (the Ruby reference + native
  # delegations answer one canonical form; re-canonicalizing it is
  # the identity).
  it "M2 canonicalization is idempotent on every adapter" do
    docs.each do |seed_tag, xml|
      adapters.each do |name|
        begin
          doc = Moxml.new(name).parse(xml)
          once = Moxml::C14n.canonicalize(doc)
          twice = Moxml::C14n.canonicalize(Moxml.new(name).parse(once))
        rescue Moxml::Error, NotImplementedError, LoadError
          next
        end
        expect(twice).to eq(once), "M2 drift #{seed_tag}/#{name}"
      end
    end
  end

  # M3: document order — XPath element results equal the pre-order
  # walk's element sequence.
  it "M3 XPath results preserve document order on every adapter" do
    docs.each do |seed_tag, xml|
      adapters.each do |name|
        begin
          doc = Moxml.new(name).parse(xml)
          via_xpath = doc.xpath("//*").to_a.map(&:name)
          via_walk = []
          doc.traverse { |n| via_walk << n.name if n.node_type == :element }
        rescue Moxml::Error, NotImplementedError, LoadError
          next
        end
        expect(via_xpath).to eq(via_walk), "M3 drift #{seed_tag}/#{name}"
      end
    end
  end

  # M4: serialization shape invariants (per shape).
  it "M4 keeps the shape contracts on every adapter" do
    docs.each do |seed_tag, xml|
      adapters.each do |name|
        begin
          ctx = Moxml.new(name)
          doc = ctx.parse(xml)
          xhtml = doc.to_xhtml
        rescue Moxml::Error, NotImplementedError, LoadError
          next # loud contracts (no HTML engine) are pinned elsewhere
        end
        expect(xhtml).not_to include("<!DOCTYPE"),
                             "M4 #{seed_tag}/#{name}: xhtml grew a doctype"
        expect(xhtml).not_to include("<?xml"),
                             "M4 #{seed_tag}/#{name}: xhtml grew a declaration"
        # The XHTML shape re-parses with the same element set (the
        # slash forms are well-formed XML).
        expect(snapshot_structure(ctx.parse(xhtml)))
          .to eq(snapshot_structure(doc)),
              "M4 #{seed_tag}/#{name}: xhtml round-trip drifted"
      end
    end
  end

  # M5: adapter-adapter equivalence on the structural information set
  # (element sequence + attribute sets). Text-level equivalence over
  # generated docs rides the taxonomy differential's registered
  # exemptions (D-13/D-14 whitespace/PI families).
  it "M5 structural equivalence across adapters" do
    docs.each do |seed_tag, xml|
      per = adapters.filter_map do |name|
        doc = Moxml.new(name).parse(xml)
        [name, snapshot_structure(doc), element_attr_set(doc)]
      rescue Moxml::Error, NotImplementedError, LoadError
        nil
      end
      next if per.size < 2

      base_name, base_struct, base_attrs = per.first
      per.each do |name, struct, attrs|
        expect(struct).to eq(base_struct),
                          "M5 structure drift #{seed_tag}/#{name} vs " \
                          "#{base_name}"
        expect(attrs).to eq(base_attrs),
                         "M5 attribute drift #{seed_tag}/#{name} vs " \
                         "#{base_name}"
      end
    end
  end
end
