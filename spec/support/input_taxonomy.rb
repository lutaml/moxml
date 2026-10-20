# frozen_string_literal: true

# The canonical input-class taxonomy (TODO.sota/01-totality): every
# class of input the processing model touches, as shared fixture data
# the differential suites consume. Adding a class here automatically
# extends the whole-class differential; a class without a stable
# cross-adapter answer must cite a registered divergence (D-ID) or a
# named raise in the consuming suite.
module InputTaxonomy
  Input = Struct.new(:id, :klass, :xml, :well_formed, :note) do
    def well_formed? = well_formed
  end

  WELL_FORMED = "well-formed"
  MALFORMED = "malformed"

  def self.all
    @all ||= inputs.freeze
  end

  def self.well_formed
    all.select(&:well_formed?)
  end

  def self.malformed
    all.reject(&:well_formed?)
  end

  def self.by_klass(klass)
    all.select { |i| i.klass == klass }
  end

  CLASSES = [
    "empty/minimal",
    "deep nesting",
    "huge text/attributes",
    "entities",
    "namespaces",
    "mixed content",
    "pi/comment/cdata edges",
    "malformed",
  ].freeze

  def self.inputs
    [
      # -- empty/minimal --
      Input.new("empty/minimal: empty string", "empty/minimal", "", false,
                "no root: parse must fail loudly or per contract"),
      Input.new("empty/minimal: whitespace only", "empty/minimal", "  \n\t ", false,
                "whitespace-only: no root"),
      Input.new("empty/minimal: bare root", "empty/minimal", "<r/>", true, nil),
      Input.new("empty/minimal: empty paired root", "empty/minimal", "<r></r>", true, nil),
      Input.new("empty/minimal: declaration only", "empty/minimal",
                '<?xml version="1.0"?>', false, "declaration without root"),

      # -- deep nesting --
      Input.new("deep nesting: 200 levels", "deep nesting",
                "<r>#{'<d>' * 200}leaf#{'</d>' * 200}</r>", true, nil),
      Input.new("deep nesting: siblings at depth", "deep nesting",
                "<r>#{'<a><b>' * 50}#{'</b></a>' * 50}</r>", true, nil),

      # -- huge text/attributes --
      Input.new("huge text: 100k chars", "huge text/attributes",
                "<r>#{'x' * 100_000}</r>", true, nil),
      Input.new("huge attribute: 10k chars", "huge text/attributes",
                %(<r a="#{'y' * 10_000}"/>), true, nil),
      Input.new("huge text with entities", "huge text/attributes",
                "<r>#{'&amp;' * 20_000}</r>", true, nil),

      # -- entities: built-in --
      Input.new("entities: all five built-ins", "entities",
                "<r>&amp;&lt;&gt;&quot;&apos;</r>", true, nil),
      # -- entities: numeric --
      Input.new("entities: decimal numeric", "entities",
                "<r>&#65;&#233;</r>", true, nil),
      Input.new("entities: hex numeric", "entities",
                "<r>&#x41;&#xE9;</r>", true, nil),
      # -- entities: custom (DTD-declared) --
      Input.new("entities: custom DTD entity", "entities",
                '<!DOCTYPE r [<!ENTITY x "expanded">]><r>&x;</r>', true, nil),
      # -- entities: undefined (disabled context) --
      Input.new("entities: undefined reference", "entities",
                "<r>&undefinedEntity;</r>", false,
                "undefined entity: malformed without a DTD"),
      Input.new("entities: NBSP char ref", "entities",
                "<r>&#160;</r>", true, "U+00A0 survives as content"),

      # -- namespaces: default --
      Input.new("namespaces: default", "namespaces",
                '<r xmlns="urn:a"><c/></r>', true, nil),
      # -- namespaces: prefixed --
      Input.new("namespaces: prefixed", "namespaces",
                '<r xmlns:p="urn:a"><p:c/></r>', true, nil),
      # -- namespaces: undeclared prefix --
      Input.new("namespaces: undeclared prefix", "namespaces",
                "<p:c/>", false,
                "undeclared prefix: malformed in strict parsing"),
      # -- namespaces: redeclared --
      Input.new("namespaces: redeclared", "namespaces",
                '<r xmlns:p="urn:a"><s xmlns:p="urn:b"><p:c/></s></r>', true, nil),
      # -- namespaces: reserved xml --
      Input.new("namespaces: reserved xml prefix", "namespaces",
                '<r xml:lang="en"/>', true, nil),
      # -- namespaces: xmlns attribute --
      Input.new("namespaces: xmlns declaration attribute", "namespaces",
                '<r xmlns="urn:a" xmlns:p="urn:b"/>', true, nil),

      # -- mixed content --
      Input.new("mixed content: text and inline", "mixed content",
                "<r>text <b>bold</b> tail</r>", true, nil),
      Input.new("mixed content: whitespace runs", "mixed content",
                "<r>\n  <b>x</b>\n  <b>y</b>\n</r>", true, nil),
      Input.new("mixed content: attribute entities in text", "mixed content",
                '<r a="&lt;&amp;">&lt;tag&gt;</r>', true, nil),

      # -- pi/comment/cdata edges --
      Input.new("pi/comment/cdata: pi before root", "pi/comment/cdata edges",
                '<?xml-stylesheet href="a"?> <r/>', true, nil),
      Input.new("pi/comment/cdata: comment before and after root", "pi/comment/cdata edges",
                "<!-- lead --><r/><!-- trail -->", true, nil),
      Input.new("pi/comment/cdata: cdata with markup", "pi/comment/cdata edges",
                "<r><![CDATA[<notmarkup> & raw]]></r>", true, nil),
      Input.new("pi/comment/cdata: empty cdata", "pi/comment/cdata edges",
                "<r><![CDATA[]]></r>", true, nil),
      Input.new("pi/comment/cdata: comment inside content", "pi/comment/cdata edges",
                "<r>a<!-- mid -->b</r>", true, nil),
      Input.new("pi/comment/cdata: pi inside content", "pi/comment/cdata edges",
                "<r>a<?pi data?>b</r>", true,
                "PI content must not contribute to text (D-14 on oga)"),

      # -- malformed: unclosed --
      Input.new("malformed: unclosed element", "malformed", "<r><c>", false, nil),
      # -- malformed: bad nest --
      Input.new("malformed: bad nesting", "malformed", "<r><a><b></a></b></r>", false, nil),
      # -- malformed: bad attribute --
      Input.new("malformed: unterminated attribute", "malformed",
                '<r a="x>', false, nil),
      # -- malformed: stray closing --
      Input.new("malformed: stray closing tag", "malformed", "</r>", false, nil),
      # -- malformed: invalid encoding bytes --
      Input.new("malformed: invalid utf-8 byte", "malformed",
                "<r>\xC3\x28</r>", false,
                "0xC3 0x28 is not valid UTF-8"),
    ].freeze
  end
end
