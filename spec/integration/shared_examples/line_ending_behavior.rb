# frozen_string_literal: true

RSpec.shared_examples "Moxml Line Ending" do
  describe "Line ending configuration" do
    let(:context) { Moxml.new }
    let(:xml) { "<root><child>text</child></root>" }

    it "produces no CRLF with LF default" do
      doc = context.parse(xml)
      expect(doc.to_xml).not_to include("\r\n")
    end

    it "produces no bare LF with CRLF configured" do
      context.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      doc = context.parse(xml)
      expect(doc.to_xml).not_to match(/(?<!\r)\n/)
    end

    it "allows per-call CRLF override producing no bare LF" do
      doc = context.parse(xml)
      output = doc.to_xml(line_ending: Moxml::Config::LINE_ENDING_CRLF)
      expect(output).not_to match(/(?<!\r)\n/)
    end

    it "per-call LF override wins over config CRLF" do
      context.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      doc = context.parse(xml)
      expect(doc.to_xml(line_ending: Moxml::Config::LINE_ENDING_LF))
        .not_to include("\r\n")
    end

    it "produces identical bytes on re-serialization with CRLF" do
      context.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      doc = context.parse(xml)
      first = doc.to_xml

      ctx2 = Moxml.new
      ctx2.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      result = ctx2.parse(first)
      expect(result.to_xml).to eq(first)
    end

    it "preserves element structure through CRLF round-trip" do
      doc = context.parse("<root><a>text</a><b>more</b></root>")
      context.config.default_line_ending = Moxml::Config::LINE_ENDING_CRLF
      crlf_output = doc.to_xml

      ctx2 = Moxml.new
      result = ctx2.parse(crlf_output)
      elements = result.root.children.select(&:element?)
      expect(elements.map(&:name)).to eq(%w[a b])
      expect(elements[0].children.first.content).to eq("text")
      expect(elements[1].children.first.content).to eq("more")
    end
  end
end
