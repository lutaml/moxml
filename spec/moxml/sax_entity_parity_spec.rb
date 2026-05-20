# frozen_string_literal: true

require "spec_helper"

# Pins cross-adapter parity for entity-decoding in attribute values and
# text content, across SAX, DOM, and build-then-serialize-then-reparse.
# Previously the four adapters diverged: nokogiri/libxml SAX failed to
# resolve "&amp;#NN;"; rexml SAX delivered raw escaped strings; oga DOM
# and SAX double-decoded.

# Namespace-isolated container for the test data and the SAX capture
# handler. Wrapping these in a module rather than declaring them as
# top-level constants inside `RSpec.describe` keeps them out of the
# global namespace and lets the spec reference them without tripping
# the RSpec/* cops that forbid local-variable use inside examples.
module SaxEntityParityFixtures
  class CaptureHandler < Moxml::SAX::ElementHandler
    attr_reader :first_attrs, :text

    def initialize
      super
      @first_attrs = nil
      @text = +""
    end

    def on_start_element(_name, attrs = {}, _namespaces = {})
      @first_attrs = attrs.dup if @first_attrs.nil?
    end

    def on_characters(chunk)
      @text << chunk
    end
  end

  ADAPTERS = %i[nokogiri ox oga rexml libxml headed_ox].freeze

  # Each row: [input XML, decoded attribute value, expected attribute
  # value as it appears in the serialized XML]. The serialized form
  # asserts what every adapter must emit byte-for-byte for the attribute.
  ATTRIBUTE_CASES = {
    "wrapped amp + decimal ref" => ['<doc x="&amp;#38;"/>', "&#38;", "&amp;#38;"],
    "wrapped amp + hex ref" => ['<doc x="&amp;#x26;"/>', "&#x26;", "&amp;#x26;"],
    "wrapped amp + non-std ref" => ['<doc x="&amp;copy;"/>', "&copy;", "&amp;copy;"],
    "wrapped amp + lt" => ['<doc x="&amp;lt;"/>', "&lt;", "&amp;lt;"],
    "wrapped amp + amp" => ['<doc x="&amp;amp;"/>', "&amp;", "&amp;amp;"],
    "two amps" => ['<doc x="&amp;&amp;"/>', "&&", "&amp;&amp;"],
    "plain amp" => ['<doc x="&amp;"/>', "&", "&amp;"],
    "plain decimal ref" => ['<doc x="&#38;"/>', "&", "&amp;"],
    "plain hex ref" => ['<doc x="&#x26;"/>', "&", "&amp;"],
    "high codepoint" => ['<doc x="&#169;"/>', "©", "©"],
    "no entities" => ['<doc x="plain"/>', "plain", "plain"],
  }.freeze

  # Each row: [input XML, decoded text, expected text as it appears in
  # serialized XML].
  TEXT_CASES = {
    "text wrapped amp + decimal" => ["<doc>&amp;#38;</doc>", "&#38;", "&amp;#38;"],
    "text wrapped amp + non-std" => ["<doc>&amp;copy;</doc>", "&copy;", "&amp;copy;"],
    "text plain amp" => ["<doc>&amp;</doc>", "&", "&amp;"],
  }.freeze

  # XML 1.0 §2.6 — entity references inside PI content are NOT resolved.
  # Every adapter must surface the literal source text. The libxml
  # adapter previously decoded these five entities via a gsub chain in
  # processing_instruction_content; pin each one explicitly.
  PI_ENTITY_CASES = {
    "&amp;" => "data &amp; more",
    "&lt;" => "data &lt; more",
    "&gt;" => "data &gt; more",
    "&quot;" => "data &quot; more",
    "&apos;" => "data &apos; more",
  }.freeze

  # Per-adapter overrides for the rebuild-path serialized form. Oga's
  # set_attribute calls preprocess_entities which marks non-standard
  # named entities so they survive serialization as "&name;" rather than
  # being escaped to "&amp;name;". This is the entity-preservation
  # feature documented in spec/moxml/adapter/entity_restoration_spec.rb
  # and spec/moxml/adapter/oga_spec.rb — not a bug.
  REBUILD_SERIALIZED_OVERRIDES = {
    oga: {
      "wrapped amp + non-std ref" => "&copy;",
    },
  }.freeze
end

RSpec.describe "SAX/DOM entity parity" do
  SaxEntityParityFixtures::ADAPTERS.each do |adapter|
    context "with #{adapter} adapter" do
      let(:ctx) { Moxml.new(adapter) }

      SaxEntityParityFixtures::ATTRIBUTE_CASES.each do |label, (xml, expected, expected_serialized)|
        it "decodes attribute via SAX: #{label}" do
          handler = SaxEntityParityFixtures::CaptureHandler.new
          ctx.sax_parse(xml, handler)
          expect(handler.first_attrs["x"]).to eq(expected)
        end

        it "decodes attribute via DOM: #{label}" do
          expect(ctx.parse(xml).root["x"]).to eq(expected)
        end

        it "serializes attribute to expected XML form: #{label}" do
          # End-to-end: parse → DOM access → set on fresh doc → serialize
          # → assert exact serialized form. This pins what the consumer
          # sees on the wire, not just what the parser delivers in memory.
          parsed_value = ctx.parse(xml).root["x"]

          doc2 = ctx.create_document
          el = doc2.create_element("doc")
          el["x"] = parsed_value
          doc2.add_child(el)

          serialized = doc2.to_xml.sub(/\A<\?[^>]*\?>\s*/, "")
          expected_form = SaxEntityParityFixtures::REBUILD_SERIALIZED_OVERRIDES.dig(adapter, label) || expected_serialized
          expect(serialized).to include(%(x="#{expected_form}"))
        end

        it "round-trips attribute through build+serialize+reparse: #{label}" do
          parsed_value = ctx.parse(xml).root["x"]

          doc2 = ctx.create_document
          el = doc2.create_element("doc")
          el["x"] = parsed_value
          doc2.add_child(el)

          serialized = doc2.to_xml.sub(/\A<\?[^>]*\?>/, "")
          expect(ctx.parse(serialized).root["x"]).to eq(parsed_value)
        end

        it "re-serializes parsed document idempotently: #{label}" do
          # Parse → serialize → re-parse → re-serialize → assert the two
          # serializations match. This catches any non-idempotent
          # mutations the adapter applies during the round-trip.
          first = ctx.parse(xml).to_xml.sub(/\A<\?[^>]*\?>\s*/, "")
          second = ctx.parse(first).to_xml.sub(/\A<\?[^>]*\?>\s*/, "")
          expect(second).to eq(first)
        end
      end

      SaxEntityParityFixtures::TEXT_CASES.each do |label, (xml, expected, expected_serialized)|
        it "decodes text via SAX: #{label}" do
          handler = SaxEntityParityFixtures::CaptureHandler.new
          ctx.sax_parse(xml, handler)
          expect(handler.text).to eq(expected)
        end

        it "decodes text via DOM: #{label}" do
          expect(ctx.parse(xml).root.text).to eq(expected)
        end

        it "serializes text to expected XML form: #{label}" do
          serialized = ctx.parse(xml).to_xml.sub(/\A<\?[^>]*\?>\s*/, "").strip
          expect(serialized).to include(">#{expected_serialized}<")
        end
      end

      it "does not double-escape '&' in a programmatically-built text node" do
        # Pins the libxml customized Text#to_xml fix: an authored "&"
        # must serialize to "&amp;" exactly once, never "&amp;amp;".
        # Regression target for adapter/customized_libxml/text.rb where
        # the previous implementation used #content (decoded text) and
        # lost the "&" → "&amp;" escape, and earlier variants risked
        # double-escaping on round-trip.
        doc = ctx.create_document
        el = doc.create_element("doc")
        el.add_child("a & b")
        doc.add_child(el)

        serialized = doc.to_xml.sub(/\A<\?[^>]*\?>\s*/, "").strip
        expect(serialized).to include(">a &amp; b<")
        expect(serialized).not_to include("&amp;amp;")

        # And the round-trip must preserve the original text exactly.
        reparsed_text = ctx.parse(serialized).root.text
        expect(reparsed_text).to eq("a & b")
      end

      # Regressions around &amp; appearing inside contexts that Oga's
      # source-level preprocessor must not touch (CDATA, comments,
      # DOCTYPE) — verified across adapters to ensure parity holds.
      it "preserves literal &amp; inside CDATA" do
        doc = ctx.parse("<doc><![CDATA[a &amp; b]]></doc>")
        expect(doc.root.text).to eq("a &amp; b")
      end

      it "preserves literal &amp; inside comment" do
        doc = ctx.parse("<doc><!-- a &amp; b --></doc>")
        comment = doc.root.children.find { |c| c.is_a?(Moxml::Comment) }
        expect(comment.content.strip).to eq("a &amp; b")
      end

      it "preserves literal U+FFFC U+FFFC user data in attribute" do
        xml = "<doc x=\"\u{FFFC}\u{FFFC} test\"/>"
        expect(ctx.parse(xml).root["x"]).to eq("\u{FFFC}\u{FFFC} test")
      end

      it "preserves literal U+FDD0 U+FDD0 user data in attribute" do
        # Single noncharacters near the Oga marker codepoints — must not
        # collide with the internal AMP_MARKER sentinel.
        xml = "<doc x=\"\u{FDD0}\u{FDD0} test\"/>"
        expect(ctx.parse(xml).root["x"]).to eq("\u{FDD0}\u{FDD0} test")
      end

      it "handles DOCTYPE with '[' in quoted system ID" do
        # System ID containing a literal "[" before the internal subset
        # opener — quote-aware DOCTYPE terminator must not pick "]>"
        # based on the bracket inside the quoted string.
        xml = %(<!DOCTYPE root SYSTEM "has[bracket"><root x="&amp;#38;"/>)
        expect(ctx.parse(xml).root["x"]).to eq("&#38;")
      end

      it "handles bare DOCTYPE with '>' in quoted system ID" do
        # Bare DOCTYPE (no internal subset) — the terminator is ">".
        # A literal ">" inside the quoted SYSTEM id must not be treated
        # as the end of the declaration. For the Oga adapter this also
        # exercises find_block_terminator's quote-aware ">" scan; if
        # the bare-DOCTYPE end was misidentified, the preprocessor
        # would rewrite "&amp;" inside the remaining quoted ID region
        # to AMP_MARKER and leak it into the serialized doctype.
        xml = %(<!DOCTYPE root SYSTEM "a>b&amp;c"><root x="&amp;#38;"/>)
        expect(ctx.parse(xml).root["x"]).to eq("&#38;")
      end

      it "handles DOCTYPE with ']>' inside a quoted entity value" do
        # Quote-aware DOCTYPE terminator must skip past a literal "]>"
        # appearing inside a quoted ExternalID / ENTITY value so the
        # internal subset terminator is matched correctly. For the Oga
        # adapter this also exercises the source-level DOCTYPE skipper;
        # native-DOCTYPE parsers must reach the same result.
        xml = '<!DOCTYPE root [ <!ENTITY foo "]>"> ]><root x="&amp;#38;"/>'
        expect(ctx.parse(xml).root["x"]).to eq("&#38;")
      end

      SaxEntityParityFixtures::PI_ENTITY_CASES.each do |entity_label, payload|
        it "preserves literal #{entity_label} inside processing instruction" do
          doc = ctx.parse("<doc><?target #{payload}?></doc>")
          pi = doc.root.children.find { |c| c.is_a?(Moxml::ProcessingInstruction) }
          expect(pi.content.strip).to eq(payload)
        end
      end
    end
  end

  # Cross-adapter equivalence: feed the same XML into every adapter and
  # assert all of them emit the same serialized attribute form. Catches
  # any regression where one adapter starts to deviate from the rest.
  describe "cross-adapter serialization equivalence" do
    def serialize_via(adapter, xml)
      ctx = Moxml.new(adapter)
      ctx.parse(xml).to_xml.sub(/\A<\?[^>]*\?>\s*/, "").strip
    end

    SaxEntityParityFixtures::ATTRIBUTE_CASES.each do |label, (xml, _expected, expected_serialized)|
      it "every adapter emits the same attribute form: #{label}" do
        results = SaxEntityParityFixtures::ADAPTERS.to_h { |a| [a, serialize_via(a, xml)] }
        results.each do |a, out|
          expect(out).to(
            include(%(x="#{expected_serialized}")),
            "#{a} produced #{out.inspect}",
          )
        end
      end
    end
  end
end
