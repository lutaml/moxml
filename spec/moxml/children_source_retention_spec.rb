# frozen_string_literal: true

require "spec_helper"

# #355: children= attaches nodes whose engine storage may be
# pool-owned by a SOURCE document (leptris absorbs/moves across
# documents by reference). The String branch's wrapper document is
# otherwise unreferenced — collected, its free can dangle the
# attached subtree (windows GC timing, standoc#1272). The element
# retains every distinct foreign source document for its lifetime.
RSpec.describe "children= source retention (#355)" do
  %i[leptris nokogiri].each do |adapter_name|
    describe "on #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      it "retains the String branch's wrapper document" do
        el = ctx.parse("<bibitem><t>old</t></bibitem>").at("//bibitem")
        el.children = "<contributor><role>author</role></contributor>"
        sources = ctx.config.adapter.attachments.get(el.native, :children_source_docs)
        expect(sources).not_to be_nil
        expect(sources.size).to eq(1)
        GC.start
        expect(el.to_xml).to include("author")
      end

      it "retains cross-document sources from the Array branch" do
        el = ctx.parse("<r/>").root
        other = ctx.parse("<other><deep>v</deep></other>")
        el.children = other.root.children.to_a
        sources = ctx.config.adapter.attachments.get(el.native, :children_source_docs)
        expect(sources).to eq([other])
        GC.start
        expect(el.to_xml).to include("deep")
      end

      it "accumulates distinct sources across repeated children= calls" do
        el = ctx.parse("<r/>").root
        other_a = ctx.parse("<a><x/></a>")
        other_b = ctx.parse("<b><y/></b>")
        el.children = other_a.root.children.to_a
        el.children = other_b.root.children.to_a
        sources = ctx.config.adapter.attachments.get(el.native, :children_source_docs)
        expect(sources).to contain_exactly(other_a, other_b)
      end

      it "does not retain the element's own document" do
        doc = ctx.parse("<r><x/></r>")
        el = doc.root
        el.children = el.children.to_a
        expect(
          ctx.config.adapter.attachments.get(el.native, :children_source_docs),
        ).to be_nil
      end
    end
  end
end
