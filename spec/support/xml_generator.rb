# frozen_string_literal: true

# Seeded XML generator (TODO.sota/02): composes random
# taxonomy-class documents — elements, text, attributes, namespaces,
# comments, PIs, CDATA — deterministic per seed. The metamorphic
# suite runs its properties over generated docs; a failing seed is a
# reproducible regression.
module XmlGenerator
  ELEMENT_NAMES = %w[r a b node item entry rec child leaf].freeze
  ATTR_NAMES = %w[id name kind type ref value flag].freeze
  TEXT_POOL = [
    "plain text", "text with spaces  ", "entities &amp; &lt;tags&gt;",
    "unicode déjà vu", "numbers 12345", "", "  ", "tail  "
  ].freeze
  PI_TARGETS = %w[render probe].freeze

  module_function

  # Deterministic RNG: Ruby's Mersenne with an explicit seed.
  def generate(seed)
    rng = Random.new(seed)
    depth = rng.rand(1..5)
    body = compose(rng, depth)
    %(<root#{attrs(rng, depth)}>#{body}</root>)
  end

  def compose(rng, depth)
    parts = []
    rng.rand(1..4).times do
      case rng.rand(depth.zero? ? 5 : 10)
      when 0..4 then parts << element(rng, depth)
      when 5 then parts << TEXT_POOL.sample(random: rng)
      when 6 then parts << "<!-- #{format('%04x', rng.rand(65_536))} -->"
      when 7 then parts << "<?#{PI_TARGETS.sample(random: rng)} d#{format('%02x', rng.rand(256))}?>"
      when 8 then parts << "<![CDATA[raw #{format('%04x', rng.rand(65_536))} <stuff>]]>"
      when 9 then parts << format("<e n=\"%d\"/>", rng.rand(100))
      end
    end
    parts.join
  end

  def element(rng, depth)
    name = ELEMENT_NAMES.sample(random: rng)
    ns = rng.rand(4).zero? ? %( xmlns="urn:g#{rng.rand(3)}") : ""
    body = depth.positive? ? compose(rng, depth - 1) : TEXT_POOL.sample(random: rng)
    "<#{name}#{ns}#{attrs(rng, depth)}>#{body}</#{name}>"
  end

  def attrs(rng, _depth)
    (0...rng.rand(0..3)).map do |i|
      %( #{ATTR_NAMES.sample(random: rng)}#{i}="v#{rng.rand(100)}")
    end.join
  end
end
