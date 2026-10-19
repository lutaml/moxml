# frozen_string_literal: true

require "spec_helper"

# Issue #400: documents are container nodes — Document#text
# concatenates descendant text (Nokogiri's Document#text contract).
# The base Node#text answered "" and silently emptied consumers'
# content-preservation checks (canon's formatter asserted through
# doc.text).
RSpec.describe "Document#text concatenates descendant text" do
  Moxml::Adapter::AVAILABLE_ADAPTERS.each do |adapter_name|
    context "with #{adapter_name}" do
      let(:ctx) { Moxml.new(adapter_name) }

      it "answers the concatenated descendant text" do
        doc = ctx.parse("<r><a>x</a><b>y</b></r>")
        expect(doc.text).to eq("xy")
      end

      it "matches root.text (both containers recurse)" do
        doc = ctx.parse("<r><a>x</a><b>y</b></r>")
        expect(doc.text).to eq(doc.root.text)
      end

      it "answers an empty string for element-free documents" do
        expect(ctx.parse("<r/>").text).to eq("")
      end
    end
  end
end
