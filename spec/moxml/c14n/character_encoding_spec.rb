# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

# TODO.c14n/13: encoding edge cases. moxml normalizes every parse to
# UTF-8 bytes and rewrites the declaration to match — engines honor
# the DECLARED encoding and would otherwise re-decode the already
# transcoded bytes into mojibake.
CAF_E_UTF8 = [60, 114, 62, 99, 97, 102, 195, 169, 60, 47, 114, 62].freeze
LATIN1_XML = (+"<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><r>caf\xE9</r>").force_encoding("ISO-8859-1")
BOM_XML = (+"\xEF\xBB\xBF<r/>").force_encoding("UTF-8")
NFC_XML = (+"<r>caf\xC3\xA9</r>").force_encoding("UTF-8")

# oga's parse layer leaks the declaration as a PI node and the BOM as
# text (pre-existing, documented in the W3C examples spec).
OGA_LEAK = %i[oga].freeze

RSpec.describe "Moxml character encoding at the parse boundary" do
  Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
    context "with the #{adapter_name} adapter" do
      let(:ctx) { Moxml.new(adapter_name) }

      unless OGA_LEAK.include?(adapter_name)
        it "transcodes declared Latin-1 to UTF-8 bytes" do
          doc = ctx.parse(LATIN1_XML.dup)
          expect(Moxml::C14n.canonicalize(doc).bytes).to eq(CAF_E_UTF8)
        end

        it "strips a leading UTF-8 BOM" do
          doc = ctx.parse(BOM_XML.dup)
          expect(Moxml::C14n.canonicalize(doc)).to eq("<r></r>")
        end
      end

      it "passes NFC content through without normalization" do
        doc = ctx.parse(NFC_XML.dup)
        expect(Moxml::C14n.canonicalize(doc).bytes).to eq(CAF_E_UTF8)
      end

      it "does not mutate the caller's input string" do
        input = LATIN1_XML.dup
        expect(input).not_to be_frozen
        ctx.parse(input)
        expect(input.encoding).to eq(Encoding::ISO_8859_1)
        expect(input.valid_encoding?).to be(true)
        expect(input.bytes).to eq(LATIN1_XML.bytes)
      end

      it "serializes transcoded documents as UTF-8 declarations" do
        doc = ctx.parse(LATIN1_XML.dup)
        expect(doc.to_xml).to include("UTF-8")
        expect(doc.to_xml).not_to include("ISO-8859-1")
      end
    end
  end
end
