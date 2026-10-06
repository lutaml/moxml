# frozen_string_literal: true

require "spec_helper"

# Signed exponent literals (libxml2/nokogiri extension): the lexer
# consumed exponent digits but not their sign, so 1E+1 tokenized as
# 1E + 1 and predicates raised "Expected ']'"; and the parser's
# numeric conversion ran to_i on dotless literals, so 2E3 evaluated
# as 2. Both fixed; the engine now matches nokogiri on every shape.
RSpec.describe "XPath exponent number literals" do
  %i[nokogiri ox].each do |adapter|
    it "evaluates signed exponents on #{adapter}" do
      ctx = Moxml.new(adapter)
      doc = ctx.parse("<r><x v='2000'/><x v='5'/></r>")
      expect(doc.xpath("//x[@v > 1E+1]").size).to eq(1)
      expect(doc.xpath("//x[@v = 2E3]").size).to eq(1)
      expect(doc.xpath("//x[@v > 5.2E-3]").size).to eq(2)
      expect(doc.xpath("//x[@v < 1e1]").size).to eq(1)
    end
  end

  it "tokenizes exponent literals as one number" do
    tokens = Moxml::XPath::Lexer.new("1E+1 2E3 5.2E-3 1e2").tokenize
    numbers = tokens.select { |t| t.first == :number }.map { |t| t[1] }
    expect(numbers).to eq(["1E+1", "2E3", "5.2E-3", "1e2"])
  end

  it "parses exponent literals at full precision" do
    ast = Moxml::XPath::Parser.parse("1E+1")
    literal = ast
    literal = literal.children.first while literal.children.any? { |c| c.respond_to?(:type) }
    expect(literal.value).to eq(10.0)
  end
end
