# frozen_string_literal: true

require "spec_helper"

# Element-level indentation is a declared capability (model, Serialization;
# D-09): engines that cannot honor the knob raise the named AdapterError
# instead of answering unindented output. indent: 0 and the no-option
# path stay common — consumers use them for canonical shapes.
RSpec.describe "element-level serialization indentation" do
  it "honors a positive indent on engines that support it" do
    %i[nokogiri rexml].each do |name|
      doc = Moxml.new(name).parse("<r><a/></r>")
      expect(doc.root.to_xml(indent: 2)).to include("\n"),
                                          "#{name}: indent not honored"
    end
  end

  it "raises the named AdapterError on engines that ignore the knob" do
    %i[oga ox headed_ox libxml leptris].each do |name|
      doc = Moxml.new(name).parse("<r><a/></r>")
      expect { doc.root.to_xml(indent: 2) }
        .to raise_error(Moxml::AdapterError, /indentation/),
            "#{name}: silent unindented answer"
    end
  end

  it "keeps indent: 0 and the no-option path common on every adapter" do
    Moxml::Adapter::AVAILABLE_ADAPTERS.each do |name|
      doc = Moxml.new(name).parse("<r><a/></r>")
      expect(doc.root.to_xml(indent: 0)).to include("<a")
      expect(doc.root.to_xml).to include("<a")
    end
  end
end
