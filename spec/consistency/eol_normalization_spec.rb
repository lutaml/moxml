# frozen_string_literal: true

require "spec_helper"

# XML 1.0 §2.11 End-of-Line Handling: literal CRLF and lone CR
# normalize to LF in parsed character data, before tokenization —
# so CDATA content normalizes too, while character references
# (&#13;) sit OUTSIDE the rule and must survive as CR. Attribute
# values normalize EOL first, then §3.3.3 maps the break to a
# space (libxml2 parity: "x\r\ny" -> "x y").
#
# Adapter status (verified 2026-09-25):
#   nokogiri/libxml - conform on all three surfaces
#   rexml           - text/cdata conform; attrs EOL-only ("x\ny")
#   ox              - text/cdata conform; attrs raw; &#13;
#                     over-normalized to \n (upstream)
#   oga             - preserves raw CR everywhere (upstream)
#   leptris         - fixed in engine 1.9.238 (leptris#1355,
#                     leptris-ruby#326); skipped below until that
#                     binding release rides.
RSpec.describe "XML line-ending normalization" do
  ADAPTERS = %i[leptris nokogiri ox oga rexml libxml].freeze # rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration

  def with_adapter(name)
    ctx = Moxml.new(name)
    yield ctx
  rescue LoadError
    skip "adapter #{name} unavailable"
  end

  def leptris_fixed?(name)
    return true unless name == :leptris

    defined?(Leptris::VERSION) &&
      Gem::Version.new(Leptris::VERSION) >= Gem::Version.new("1.9.238")
  end

  it "normalizes CRLF and lone CR to LF in text content" do
    ADAPTERS.each do |name|
      next unless leptris_fixed?(name)

      skip "oga preserves raw CR (upstream)" if name == :oga

      with_adapter(name) do |ctx|
        text = ctx.parse("<r>a\r\nb\rc</r>").root.children.first
        expect(text.content).to eq("a\nb\nc"), "#{name}: #{text.content.inspect}"
      end
    end
  end

  it "normalizes EOL inside CDATA content" do
    ADAPTERS.each do |name|
      next unless leptris_fixed?(name)

      skip "oga preserves raw CR (upstream)" if name == :oga

      with_adapter(name) do |ctx|
        cdata = ctx.parse("<r><![CDATA[a\r\nb]]></r>").root.children.first
        expect(cdata.content).to eq("a\nb"), "#{name}: #{cdata.content.inspect}"
      end
    end
  end

  it "preserves CR from character references" do
    ADAPTERS.each do |name|
      next unless leptris_fixed?(name)

      skip "ox collapses &#13; to LF (upstream)" if name == :ox
      skip "oga preserves raw CR (upstream)" if name == :oga

      with_adapter(name) do |ctx|
        text = ctx.parse("<r>a&#13;b</r>").root.children.first
        expect(text.content).to eq("a\rb"), "#{name}: #{text.content.inspect}"
      end
    end
  end

  it "collapses attribute CRLF to a single space (libxml2 parity)" do
    conforming = %i[nokogiri libxml leptris]
    conforming.each do |name|
      next unless leptris_fixed?(name)

      with_adapter(name) do |ctx|
        root = ctx.parse("<r a=\"x\r\ny\" b=\"x\ty\"/>").root
        expect(root["a"]).to eq("x y"), "#{name}: attr CRLF #{root['a'].inspect}"
        expect(root["b"]).to eq("x y"), "#{name}: attr tab #{root['b'].inspect}"
      end
    end
  end
end
