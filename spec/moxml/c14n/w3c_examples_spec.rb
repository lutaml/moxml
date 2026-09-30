# frozen_string: true

require "spec_helper"
require "moxml/c14n"

# Shapes drawn from the W3C Canonical XML 1.0 REC examples (§2–§3):
# attribute-value whitespace normalization, character-reference CR
# preservation vs literal-CR folding, CDATA as character data, empty
# element form, PI/comment placement, and the §3 document-subset
# whitespace rules. Expected bytes are the forms all conformant
# adapters answer identically.
#
# Documented parse-layer divergences (skipped rows):
# - ox/headed_ox expand &#xD; to LF, strip inter-element whitespace
#   and comment padding at parse (out of scope here)
# - oga keeps the target/content separator space in PI data
W3C_FULL_FORMS = [
  ["attribute-value whitespace collapses to single spaces",
   "<doc>\n   <e   attr1=\"v1\"\n        attr2   =   \"v2\"\n    >   content   </e>\n</doc>",
   "<doc>\n   <e attr1=\"v1\" attr2=\"v2\">   content   </e>\n</doc>"],
  ["character-reference CR stays &#xD;; literal CR folds to LF",
   %(<doc>a&#xD;b\nc&#xA;d</doc>),
   %(<doc>a&#xD;b\nc\nd</doc>)],
  ["CDATA is character data and escapes",
   %(<doc><![CDATA[a<b]]> &amp; &lt; x</doc>),
   %(<doc>a&lt;b &amp; &lt; x</doc>)],
  ["empty elements render as start and end tags",
   %(<doc><e/><f></f></doc>),
   "<doc><e></e><f></f></doc>"],
  ["PIs render in place; comments drop without with_comments",
   %(<doc><?pi c?><!-- c1 --><e/><!-- c2 --></doc>),
   %(<doc><?pi c?><e></e></doc>)],
].freeze

W3C_SUBSET_FORM = [
  %(<doc>\n   <e1 a="1" b="2"/>\n   <e2/>\n   <e3/>\n   <!-- A small comment -->\n   <?pi x?>\n</doc>),
  "//e1 | //e2 | //e3",
  %(<e1 a="1" b="2"></e1><e2></e2><e3></e3>),
].freeze

W3C_SUBSET_WITH_ROOT = [
  %(<doc>\n   <e1 a="1" b="2"/>\n   <e2/>\n   <e3/>\n   <!-- A small comment -->\n   <?pi x?>\n</doc>),
  "/doc | //e1 | //e2 | //e3",
  %(<doc>\n   <e1 a="1" b="2"></e1>\n   <e2></e2>\n   <e3></e3>\n   \n   \n</doc>),
].freeze

CR_SHAPE = 1
PI_SHAPE = 4
WHITESPACE_SHAPES = %i[ox headed_ox].freeze

RSpec.describe "Moxml::C14n W3C REC-xml-c14n examples" do
  Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
    context "with the #{adapter_name} adapter" do
      let(:ctx) { Moxml.new(adapter_name) }

      W3C_FULL_FORMS.each_with_index do |(label, xml, expected), idx|
        # ox/headed_ox strip inter-element whitespace, expand &#xD;
        # and pad comments at parse; oga keeps the PI separator space.
        skip_shapes = { ox: [0, CR_SHAPE, PI_SHAPE],
                        headed_ox: [0, CR_SHAPE, PI_SHAPE],
                        oga: [PI_SHAPE] }[adapter_name] || []
        next if skip_shapes.include?(idx)

        it "canonicalizes #{label}" do
          doc = ctx.parse(xml)
          expect(Moxml::C14n.canonicalize_inclusive10(doc)).to eq(expected)
          expect(Moxml::C14n.canonicalize(doc.root)).to eq(expected)
        end
      end
    end
  end

  describe "W3C §3 document-subset whitespace" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
      next if WHITESPACE_SHAPES.include?(adapter_name)

      it "renders selected nodes only, whitespace runs in place (#{adapter_name})" do
        doc = Moxml.new(adapter_name).parse(W3C_SUBSET_FORM[0])
        expect(Moxml::C14n.canonicalize_subset(doc, W3C_SUBSET_FORM[1]))
          .to eq(W3C_SUBSET_FORM[2])
      end

      it "keeps the root's whitespace runs when the root is selected (#{adapter_name})" do
        doc = Moxml.new(adapter_name).parse(W3C_SUBSET_WITH_ROOT[0])
        expect(Moxml::C14n.canonicalize_subset(doc, W3C_SUBSET_WITH_ROOT[1]))
          .to eq(W3C_SUBSET_WITH_ROOT[2])
      end
    end
  end

  describe "Ruby reference agrees with the native engines" do
    %i[leptris nokogiri].each do |adapter_name|
      next unless Moxml::Adapter::AVAILABLE_ADAPTERS.include?(adapter_name)

      it "on every full-document shape (#{adapter_name})" do
        W3C_FULL_FORMS.each do |_label, xml, _expected|
          root = Moxml.new(adapter_name).parse(xml).root
          expect(Moxml::C14n.canonicalize(root))
            .to eq(Moxml::C14n.canonicalize_inclusive10(root))
        end
      end
    end
  end
end
