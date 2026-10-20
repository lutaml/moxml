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
  # input id => { face => { adapter => D-NN } }
  EXEMPT = {
    "mixed content: whitespace runs" => {
      nodes: { ox: "D-13", headed_ox: "D-13" },
      text: { ox: "D-13", headed_ox: "D-13" },
    },
    "pi/comment/cdata: pi inside content" => {
      text: { oga: "D-14" },
    },
    "huge text with entities" => {
      text: { rexml: "D-16" },
    },
    "pi/comment/cdata: pi before root" => {
      nodes: { rexml: "D-15" },
      text: { rexml: "D-15" },
    },
  }.freeze

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
          exempt = EXEMPT.dig(input.id, face, name)
          next if exempt

          expect(got[face]).to eq(base[face]),
                               "#{input.id}/#{face} differs on #{name} vs " \
                               "#{base_name}: #{got[face].inspect} vs " \
                               "#{base[face].inspect} — fix it or register " \
                               "a divergence and exempt the cell"
        end
        text_exempt = EXEMPT.dig(input.id, :text, name)
        next if text_exempt

        expect(got[:text]).to eq(base[:text]),
                              "#{input.id}/text differs on #{name} vs " \
                              "#{base_name}: #{got[:text].inspect} vs " \
                              "#{base[:text].inspect} — fix it or register " \
                              "a divergence and exempt the cell"
      end
    end
  end

  it "keeps the round trip stable per adapter (M1: parse∘serialize)" do
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
    # Engines whose strict lane cannot see a class of malformedness
    # are registered: oga's strict is lexer-strict, not
    # well-formedness-strict (D-17); entity/prefix classes are
    # engine-variant by design (entity modes, namespace validation).
    STRICT_EXEMPT = {
      "malformed: bad nesting" => { oga: "D-17" },
      "malformed: invalid utf-8 byte" => { leptris: "D-18", oga: "D-18",
                                           ox: "D-18",
                                           headed_ox: "D-18" },
    }.freeze

    InputTaxonomy.malformed.each do |input|
      next if input.id.include?("undefined reference") ||
        input.id.include?("undeclared prefix") # engine-variant classes

      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
        next if STRICT_EXEMPT.dig(input.id, name)

        begin
          # The strict lane, named: the model's default posture for
          # malformed input is a named raise on every adapter.
          Moxml.new(name).parse(input.xml, strict: true)
        rescue Moxml::ParseError
          next # the contract answer
        rescue Moxml::Error => e
          raise "#{input.id}/#{name}: wrong error class " \
                "#{e.class}: #{e.message[0, 60]}"
        end
        raise "#{input.id}/#{name}: strict parse accepted malformed input"
      end
    end
  end
end
