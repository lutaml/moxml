# frozen_string_literal: true

require "spec_helper"
require "support/input_taxonomy"
require "support/input_generator"

# Metamorphic property suite (TODO.sota/02): generated evidence over
# the 01 taxonomy's vocabulary, seeded per run — SOTA_FUZZ_SEEDS
# (default fixed, identical cases every CI run; the nightly fuzz leg
# passes a random comma-separated list) and SOTA_FUZZ_CASES per seed
# (bounded per leg).
#
# M1 round trip, M2 c14n idempotence, M3 document-order/union order,
# M4 serialization shape, M5 cross-adapter answer equality modulo the
# register; the malformed class raises the named ParseError
# everywhere. Failures name the case id ("gen <seed>/<i>") —
# reproducible at that seed and index — and the cell.
RSpec.describe "metamorphic properties (generated, seeded)" do
  let(:fuzz_seeds) do
    if ENV.key?("SOTA_FUZZ_SEEDS")
      ENV.fetch("SOTA_FUZZ_SEEDS").split(",").map(&:to_i)
    else
      [20261020]
    end
  end

  let(:fuzz_count) { Integer(ENV.fetch("SOTA_FUZZ_CASES", "200")) }

  let(:cases) do
    fuzz_seeds.flat_map do |seed|
      InputGenerator.cases(seed: seed, count: fuzz_count)
    end
  end

  def snapshot(doc)
    {
      nodes: doc.traverse.to_a.grep_v(Moxml::Document).count,
      root: doc.root&.name,
      text: doc.text,
      xpath: doc.xpath("//*").to_a.count,
    }
  end

  def compact(snap)
    snap.except(:nodes).merge(text: snap[:text].gsub(/\s+/, ""))
  end

  def exempt?(input, face, name)
    input.features.any? do |feature|
      InputGenerator::FEATURE_EXEMPT.dig(feature, face, name)
    end
  end

  it "M1: keeps the round trip stable per adapter over generated inputs" do
    cases.each do |input|
      next unless input.well_formed

      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        begin
          ctx = Moxml.new(name)
          first = snapshot(ctx.parse(input.xml))
          second = snapshot(ctx.parse(ctx.parse(input.xml).to_xml(indent: 0)))
        rescue Moxml::Error, NotImplementedError, LoadError
          next # adapter unavailable or a named guard excuses the leg
        end
        expect(compact(second)).to eq(compact(first)),
                                   "#{input.id} round-trip drifted on " \
                                   "#{name}: #{first.inspect} vs " \
                                   "#{second.inspect}"
      end
    end
  end

  it "M2: canonicalization is idempotent (c14n∘c14n == c14n)" do
    c14n = Moxml::C14n::Inclusive10.new
    cases.each do |input|
      next unless input.well_formed

      once = c14n.canonicalize(input.xml)
      expect(c14n.canonicalize(once)).to eq(once),
                                         "#{input.id}: c14n is not " \
                                         "idempotent"
    end
  end

  it "M3: XPath unions answer in first-encounter (document) order" do
    # XPath 1.0 unprefixed name tests match no-namespace elements
    # only (processing model, "Names and namespaces") — the union
    # property is scoped to cases an unprefixed query can address.
    addressed = cases.select do |input|
      input.well_formed && !input.features.include?(:default_ns)
    end
    addressed.each do |input|
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        begin
          doc = Moxml.new(name).parse(input.xml)
          union = doc.xpath("//a | //b").to_a.map(&:name)
        rescue Moxml::Error, NotImplementedError, LoadError
          next # adapter unavailable in this environment
        end
        wanted = %w[a b]
        doc_order = doc.traverse.to_a
          .grep(Moxml::Element)
          .map(&:name)
          .select { |n| wanted.include?(n) }
        expect(union).to eq(doc_order),
                         "#{input.id}: union order diverges from document " \
                         "order on #{name}: #{union.inspect} vs " \
                         "#{doc_order.inspect}"
      end
    end
  end

  it "M4: to_html and to_xhtml hold their serialization shape" do
    cases.each do |input|
      next if !input.well_formed || input.voids.empty?

      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        begin
          doc = Moxml.new(name).parse(input.xml)
          html = doc.to_html
          xhtml = doc.to_xhtml
        rescue Moxml::Error, NotImplementedError, LoadError
          next # the HTML face is adapter-optional (loud raise where absent)
        end
        expect(html).not_to include("<?xml"),
                            "#{input.id}: to_html declared XML on #{name}"
        input.voids.each do |v|
          expect(html).not_to match(%r{<#{v}\b[^>]*/>}),
                              "#{input.id}: to_html self-closed void <#{v}> " \
                              "on #{name}"
        end
        # "none of the HTML short forms": a bare <br> is not XML,
        # so the strict re-parse is the rigorous check (self-closed
        # and paired forms are both legal XHTML).
        expect { Moxml.new(:leptris).parse(xhtml, strict: true) }
          .not_to raise_error,
                  "#{input.id}: to_xhtml left an HTML short form on " \
                  "#{name}: #{xhtml[0, 120].inspect}"
      end
    end
  end

  it "M5: every adapter answers generated inputs identically, modulo the register" do
    cases.each do |input|
      next unless input.well_formed

      per = Moxml::Adapter::AVAILABLE_ADAPTERS.filter_map do |name|
        [name, snapshot(Moxml.new(name).parse(input.xml))]
      rescue Moxml::Error, NotImplementedError, LoadError
        nil # adapter unavailable in this environment
      end.to_h
      expect(per.keys.count).to be >= 2

      base_name = per.keys.first
      base = per[base_name]
      per.each do |name, got|
        base.except(:text).each_key do |face|
          next if exempt?(input, face, name)

          expect(got[face]).to eq(base[face]),
                               "#{input.id}/#{face} differs on #{name} vs " \
                               "#{base_name}: #{got[face].inspect} vs " \
                               "#{base[face].inspect} — fix it or register " \
                               "a divergence and exempt the cell"
        end
        next if exempt?(input, :text, name)

        expect(got[:text]).to eq(base[:text]),
                              "#{input.id}/text differs on #{name} vs " \
                              "#{base_name}: #{got[:text].inspect} vs " \
                              "#{base[:text].inspect} — fix it or register " \
                              "a divergence and exempt the cell"
      end
    end
  end

  it "raises the named parse error on generated malformed input, everywhere" do
    cases.each do |input|
      next if input.well_formed

      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        # oga's strict lane is lexer-strict, not
        # well-formedness-strict (D-17) — structural malformations
        # parse there; every other adapter must raise the named error.
        next if name == :oga # D-17

        expect { Moxml.new(name).parse(input.xml, strict: true) }
          .to raise_error(Moxml::ParseError),
              "#{input.id}: #{name} accepted malformed input or raised " \
              "outside the named ParseError contract"
      end
    end
  end
end
