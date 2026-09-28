# frozen_string_literal: true

require "spec_helper"
require "moxml/c14n"

SIG = "<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\"><SignedInfo>" \
      "<m xmlns=\"urn:m\">x</m></SignedInfo><Object>o</Object></Signature>"
ENVELOPED_DOC = %(<env><payload id="p1">data &amp; more</payload>#{SIG}<tail/></env>).freeze
ENVELOPED_EXCLUDE = '//*[not(ancestor-or-self::*[local-name()="Signature"])]'
SIGNATURE_XPATH = '//*[local-name()="Signature"]'

CORPUS = [
  ["apex attraction + text",
   %(<a xml:lang="en"><b id="1"><c>t</c></b><d/></a>), "//b",
   %(<b id="1" xml:lang="en"></b>)],
  ["explicit descendant inclusion",
   %(<a xml:lang="en"><b id="1"><c>t</c></b><d/></a>), "//b | //c",
   %(<b id="1" xml:lang="en"><c>t</c></b>)],
  ["direct character data of a matched element",
   %(<a><b>t</b><d/></a>), "//b", "<b>t</b>"],
  ["unmatched child element excluded",
   %(<a><b><c>t</c></b></a>), "//b", "<b></b>"],
  ["excluded sibling subtree",
   %(<a><b><c/></b><d/></a>), "//*[not(self::d)]",
   %(<a><b><c></c></b></a>)],
  ["attribute-only selection renders nothing",
   %(<a><b id="1"/></a>), "//@id", ""],
  # C14N renders a text-only node-set without its omitted parents.
  ["text selection", %(<a><b>t1</b><b>t2</b></a>), "//b/text()", "t1t2"],
  ["empty result", %(<a><b/></a>), "//missing", ""],
].freeze

COMMENTS_CASE = [
  "with_comments keeps matched comments only",
  %(<a><!-- keep --><b><!-- in --><c/></b></a>), "//b",
  %(<b><!-- in --></b>)
].freeze

COMMENTS_PADDING_LOSS = %i[ox headed_ox].freeze

RSpec.describe "Moxml::C14n subset canonicalization" do
  # Node-set semantics follow the enveloped-signature interop
  # (libxml2/xmlsec): a matched element renders with its namespaces,
  # attributes and non-element children; child ELEMENTS need their
  # own match, so an excluded subtree stays excluded under matched
  # ancestors. Inheritable xml:* attributes of omitted ancestors and
  # apex namespace attraction still render (spec §2.3/§2.4/§3).
  describe "byte-identical subset canonical form across adapters" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
      context "with the #{adapter_name} adapter" do
        let(:ctx) { Moxml.new(adapter_name) }

        CORPUS.each do |label, xml, xpath, expected|
          next if label == "text selection" && adapter_name == :rexml

          # rexml's adapter xpath does not return text nodes for
          # text() node tests (pre-existing capability gap).

          it "canonicalizes #{label}" do
            doc = ctx.parse(xml)
            expect(Moxml::C14n.canonicalize_subset(doc, xpath)).to eq(expected)
          end
        end

        # ox/headed_ox strip comment content padding at the parse
        # layer (pre-existing, same family as their PI content loss).
        unless COMMENTS_PADDING_LOSS.include?(adapter_name)
          it COMMENTS_CASE[0] do
            doc = ctx.parse(COMMENTS_CASE[1])
            expect(Moxml::C14n.canonicalize_subset(doc, COMMENTS_CASE[2],
                                                   with_comments: true))
              .to eq(COMMENTS_CASE[3])
          end
        end
      end
    end
  end

  describe "enveloped-signature oracle" do
    it "equals canonicalizing the DOM with the Signature removed" do
      Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
        subset = Moxml::C14n.canonicalize_subset(
          Moxml.new(adapter_name).parse(ENVELOPED_DOC), ENVELOPED_EXCLUDE
        )

        doc = Moxml.new(adapter_name).parse(ENVELOPED_DOC)
        doc.root.xpath(SIGNATURE_XPATH).to_a[0].remove
        removed = Moxml::C14n.canonicalize(doc.root)

        expect(subset).to eq(removed)
      end
    end
  end

  describe "input forms" do
    let(:ctx) { Moxml.new(:leptris) }

    it "accepts an XML string" do
      expect(Moxml::C14n.canonicalize_subset(%(<a><b>t</b></a>), "//b"))
        .to eq("<b>t</b>")
    end

    it "accepts an element source, paths relative to it" do
      doc = ctx.parse(%(<a><b><c>t</c></b></a>))
      b = doc.root.xpath("//b").to_a[0]
      expect(Moxml::C14n.canonicalize_subset(b, ".//c")).to eq("<c>t</c>")
    end
  end
end
