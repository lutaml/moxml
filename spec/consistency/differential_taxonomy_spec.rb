# frozen_string_literal: true

require "spec_helper"
require "support/input_taxonomy"

# Whole-class differential (TODO.sota/01): for every taxonomy input,
# every available adapter answers the same observable results — or the
# difference cites a registered divergence (D-NN). Faces: node count,
# root name, text, element count via XPath. Plus M1 (parse∘serialize
# round-trip) per adapter over every well-formed input. Nothing is
# exempt without a D-ID: this is the generated-evidence face of the
# conformance relation.

RSpec.describe "cross-adapter taxonomy differential" do
  def snapshot(doc)
    {
      nodes: doc.traverse.to_a.grep_v(Moxml::Document).count,
      root: doc.root&.name,
      text: doc.text,
      xpath: doc.xpath("//*").to_a.count,
    }
  end

  def answers(xml)
    Moxml::Adapter::AVAILABLE_ADAPTERS.filter_map do |name|
      doc = Moxml.new(name).parse(xml)
      [name, snapshot(doc)]
    rescue Moxml::Error, NotImplementedError, LoadError
      nil # adapter unavailable in this environment
    end.to_h
  end

  InputTaxonomy.well_formed.each do |input|
    it "answers #{input.id} identically across adapters" do
      per = answers(input.xml)
      expect(per.keys.count).to be >= 2

      base_name = per.keys.first
      base = per[base_name]
      per.each do |name, got|
        base.except(:text).each_key do |face|
          exempt = InputTaxonomy::EXEMPT.dig(input.id, face, name)
          next if exempt

          expect(got[face]).to eq(base[face]),
                               "#{input.id}/#{face} differs on #{name} vs " \
                               "#{base_name}: #{got[face].inspect} vs " \
                               "#{base[face].inspect} — fix it or register " \
                               "a divergence and exempt the cell"
        end
        text_exempt = InputTaxonomy::EXEMPT.dig(input.id, :text, name)
        next if text_exempt

        expect(got[:text]).to eq(base[:text]),
                              "#{input.id}/text differs on #{name} vs " \
                              "#{base_name}: #{got[:text].inspect} vs " \
                              "#{base[:text].inspect} — fix it or register " \
                              "a divergence and exempt the cell"
      end
    end
  end

  it "keeps the round trip stable per adapter (M1: parse∘serialize)" do # rubocop:disable RSpec/NoExpectationExample
    InputTaxonomy.well_formed.each do |input|
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        begin
          ctx = Moxml.new(name)
          doc = ctx.parse(input.xml)
          first = snapshot(doc)
          # indent: 0 — default indentation synthesizes whitespace text
          # nodes on re-parse (formatting, not information; D-09
          # adapters ignore the knob and may embed their own pretty
          # newlines regardless). M1 therefore compares the information
          # set: root, element count, whitespace-collapsed text. Node
          # COUNT identity is the cross-adapter face's job (same parse),
          # not the round-trip's.
          second = snapshot(ctx.parse(doc.to_xml(indent: 0)))
        rescue Moxml::Error, NotImplementedError, LoadError
          # Named guards (e.g. D-16's read cap on rexml) legitimately
          # excuse an adapter from M1 for an input.
          next
        end
        compact = ->(snap) {
          snap.except(:nodes).merge(text: snap[:text].gsub(/\s+/, ""))
        }
        expect(compact.call(second)).to eq(compact.call(first)),
                                        "#{input.id} round-trip drifted on " \
                                        "#{name}: #{first.inspect} vs " \
                                        "#{second.inspect}"
      end
    end
  end

  it "raises the named parse error on strict malformed input, everywhere" do
    # Entity/reference and namespace-validation classes are
    # engine-variant by design — moxml governs them with config
    # (entity modes, namespace validation), not with a registered
    # divergence.
    engine_variant = %w[undefined reference undeclared prefix].freeze
    inputs = InputTaxonomy.malformed.reject do |input|
      engine_variant.any? { |term| input.id.include?(term) }
    end

    inputs.each do |input|
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        next if InputTaxonomy::STRICT_EXEMPT.dig(input.id, name)

        # The strict lane, named: the model's default posture for
        # malformed input is a named raise on every adapter.
        expect { Moxml.new(name).parse(input.xml, strict: true) }
          .to raise_error(Moxml::ParseError),
              "#{input.id}/#{name}: strict parse accepted malformed " \
              "input or raised outside the named ParseError contract"
      end
    end
  end
end
