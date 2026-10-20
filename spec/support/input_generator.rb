# frozen_string_literal: true

# Seeded XML input generator (TODO.sota/02): composes the 01
# taxonomy's vocabulary into fresh inputs, deterministically from a
# seed. CI legs run a fixed seed — identical cases every run; the
# nightly fuzz leg passes a random one (MOXML_FUZZ_SEED). Every case
# id carries its provenance ("gen <seed>/<i> <malform>"), so a
# failure reproduces at that seed and index.
module InputGenerator
  # Generated inputs record the divergence-relevant features they use
  # so the differential exempts exactly those cells, never silently —
  # every value is a register ID (docs/_pages/divergences.adoc).
  FEATURE_EXEMPT = {
    inter_element_ws: {
      nodes: { ox: "D-13", headed_ox: "D-13" },
      text: { ox: "D-13", headed_ox: "D-13" },
    },
    pi_in_content: { text: { oga: "D-14" } },
    pre_root_ws: { nodes: { rexml: "D-15" }, text: { rexml: "D-15" } },
    adjacent_cdata: {
      nodes: { oga: "D-19", rexml: "D-19", ox: "D-19", headed_ox: "D-19",
               leptris: "D-19" },
    },
  }.freeze

  # malform is one of the three guaranteed-breaking structural
  # mutations; oga's strict lane is lexer-strict (D-17) and is
  # exempted for all of them in the strict-raise property.
  Case = Struct.new(:id, :xml, :well_formed, :features, :voids, :malform)

  ELEMENTS = %w[a b sec p].freeze
  VOIDS = %w[br img hr].freeze
  ATTR_VALUES = [
    "1", "x y", "a &amp; b", "&lt;tag&gt;", "&#65;&#x42;", "taillé"
  ].freeze
  TEXTS = [
    "plain text", "  spaced  ", "a &amp; b &lt; c", "&#65;&#x42;",
    "café &#160; NBSP", "word"
  ].freeze
  NAMESPACES = [
    'xmlns="urn:t"', 'xmlns:ns="urn:n"', 'xmlns="urn:r"'
  ].freeze
  XML_ATTRS = ['xml:space="preserve"', 'xml:lang="en"'].freeze
  MALFORMS = %i[unclosed stray attr_quote].freeze

  module_function

  # mode: :fuzz mixes the three structural malformations into roughly
  # a third of the cases (the strict-raise property consumes those);
  # :well_formed answers pure compositions.
  def cases(seed:, count:, mode: :fuzz)
    rng = Random.new(seed)
    Array.new(count) do |i|
      body, features, voids = compose(rng)
      id = "gen #{seed}/#{i}"
      if mode == :fuzz && rng.rand(3).zero?
        malform = MALFORMS[rng.rand(MALFORMS.length)]
        Case.new("#{id} #{malform}", mutate(body, malform), false,
                 features, voids, malform)
      else
        Case.new(id, body, true, features, voids, nil)
      end
    end
  end

  def compose(rng)
    features = []
    voids = []
    pre = +""
    draw = rng.rand(6)
    if draw.zero?
      pre << "<!--pre-root-->"
    elsif draw == 1
      pre << "<?prep root?>"
    elsif draw == 2
      pre << "  "
      features << :pre_root_ws
    end

    attrs = +'<r id="root"'
    attrs << " #{NAMESPACES[rng.rand(NAMESPACES.length)]}" if rng.rand(2).zero?
    attrs << " #{XML_ATTRS[rng.rand(XML_ATTRS.length)]}" if rng.rand(3).zero?
    attrs << ' ns:x="v"' if rng.rand(3).zero?
    attrs << ">"

    body = +""
    depth = 1 + rng.rand(4)
    (1 + rng.rand(4)).times { body << child(rng, 0, depth, features, voids) }
    # a whitespace-only run between two constructs is a dropped-text
    # divergence cell (D-13 on ox/headed_ox)
    features << :inter_element_ws if body.match?(%r{>\s+<})

    xml = "#{pre}#{attrs}#{body}</r>"
    # a default-namespace declaration scopes XPath name tests away
    # from generated a/b elements (XPath 1.0, processing model
    # "Names and namespaces")
    features << :default_ns if xml.include?('xmlns="')
    # adjacent text-like leaves — CDATA next to CDATA/text — coalesce
    # on the libxml2 lane (D-19)
    if xml.match?(/]\]>\s*<!\[CDATA\[/) || xml.match?(/]\]>\s*[^<\s]/) ||
        xml.match?(/[^<\s]\s*<!\[CDATA\[/)
      features << :adjacent_cdata
    end
    [xml, features.uniq, voids.uniq]
  end

  def child(rng, level, max_depth, features, voids)
    if level < max_depth && rng.rand(8) < 5
      inner = +""
      (1 + rng.rand(3)).times do
        inner << child(rng, level + 1, max_depth, features, voids)
      end
      name = ELEMENTS[rng.rand(ELEMENTS.length)]
      extra = +""
      extra << " #{NAMESPACES[rng.rand(NAMESPACES.length)]}" if rng.rand(4).zero?
      extra << " #{XML_ATTRS[rng.rand(XML_ATTRS.length)]}" if rng.rand(4).zero?
      extra << " ns:x=\"#{ATTR_VALUES[rng.rand(ATTR_VALUES.length)]}\"" if rng.rand(3).zero?
      "<#{name}#{extra}>#{inner}</#{name}>"
    else
      leaf(rng, features, voids)
    end
  end

  def leaf(rng, features, voids)
    case rng.rand(6)
    when 0, 1
      TEXTS[rng.rand(TEXTS.length)]
    when 2
      "<!--comment #{rng.rand(9)}-->"
    when 3
      features << :pi_in_content
      "<?inst data-#{rng.rand(9)}?>"
    when 4
      "<![CDATA[x < #{rng.rand(9)} & more]]>"
    else
      v = VOIDS[rng.rand(VOIDS.length)]
      voids << v
      "<#{v}/>"
    end
  end

  # Each mutation is guaranteed to break well-formedness (the root
  # close and the root id attribute always exist in composed bodies).
  def mutate(xml, malform)
    case malform
    when :unclosed
      xml.sub(%r{</[a-z]+>}, "")
    when :stray
      "#{xml}</r>"
    when :attr_quote
      xml.sub('id="root"', 'id="root')
    end
  end
end
