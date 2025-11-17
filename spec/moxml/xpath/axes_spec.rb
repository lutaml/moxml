# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XPath Axes" do
  let(:context) { Moxml.new(:nokogiri) }
  let(:doc) do
    xml = <<~XML
      <root>
        <parent id="p1">
          <child id="c1">
            <grandchild id="g1">text1</grandchild>
          </child>
          <child id="c2">
            <grandchild id="g2">text2</grandchild>
          </child>
        </parent>
      </root>
    XML
    context.parse(xml)
  end

  describe "Implemented Axes" do
    it "lists all implemented axes" do
      compiler = Moxml::XPath::Compiler.new

      axes = [
        "child", "self", "parent",
        "descendant", "descendant_or_self", "attribute",
        "ancestor", "ancestor_or_self",
        "following_sibling", "preceding_sibling",
        "following", "preceding", "namespace"
      ]

      implemented = axes.select do |axis|
        compiler.respond_to?(:"on_axis_#{axis}", true)
      end

      puts "\nImplemented Axes: #{implemented.size}/13"
      implemented.each { |a| puts "  ✓ #{a}" }

      missing = axes - implemented
      if missing.any?
        puts "\nMissing Axes: #{missing.size}/13"
        missing.each { |a| puts "  ✗ #{a}" }
      end

      # Expect at least 6 axes (3 original + 3 new critical axes)
      expect(implemented.size).to be >= 6
      expect(implemented).to include("child", "self", "parent")
      expect(implemented).to include("descendant_or_self", "attribute",
                                     "descendant")
    end
  end

  describe "Critical Axes" do
    describe "child axis" do
      it "selects direct children only" do
        ast = Moxml::XPath::Parser.parse("/root/child::parent")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(1)
        expect(result.first.attribute("id").value).to eq("p1")
      end

      it "does not select grandchildren" do
        ast = Moxml::XPath::Parser.parse("/root/child::child")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result).to be_empty
      end
    end

    describe "self axis" do
      it "selects the context node" do
        ast = Moxml::XPath::Parser.parse("/root/self::root")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(1)
        expect(result.first.name).to eq("root")
      end
    end

    describe "parent axis" do
      it "selects parent of children" do
        ast = Moxml::XPath::Parser.parse("/root/parent/child/parent::parent")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(2) # Two children, both have same parent
        expect(result.first.attribute("id").value).to eq("p1")
      end
    end

    describe "descendant-or-self axis (enables //)" do
      it "finds all descendant nodes including self" do
        ast = Moxml::XPath::Parser.parse("/root/descendant-or-self::root")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(1)
        expect(result.first.name).to eq("root")
      end

      it "finds deep descendants" do
        ast = Moxml::XPath::Parser.parse("/root/descendant-or-self::grandchild")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(2)
        expect(result.map do |n|
          n.attribute("id").value
        end).to contain_exactly("g1", "g2")
      end

      it "powers the // operator" do
        ast = Moxml::XPath::Parser.parse("//grandchild")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(2)
      end
    end

    describe "attribute axis (enables @)" do
      let(:attr_doc) do
        xml = <<~XML
          <root>
            <item id="1" name="first" type="A"/>
            <item id="2" name="second" type="B"/>
          </root>
        XML
        context.parse(xml)
      end

      it "selects specific attribute" do
        ast = Moxml::XPath::Parser.parse("/root/item/attribute::id")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(attr_doc)

        expect(result.size).to eq(2)
        expect(result.map(&:value)).to contain_exactly("1", "2")
      end

      it "selects all attributes with wildcard" do
        ast = Moxml::XPath::Parser.parse("/root/item/attribute::*")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(attr_doc)

        # 2 items × 3 attributes each = 6
        expect(result.size).to eq(6)
      end

      it "powers the @ operator" do
        ast = Moxml::XPath::Parser.parse("/root/item/@name")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(attr_doc)

        expect(result.size).to eq(2)
        expect(result.map(&:value)).to contain_exactly("first", "second")
      end
    end

    describe "descendant axis" do
      it "finds descendants without self" do
        ast = Moxml::XPath::Parser.parse("/root/descendant::child")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        expect(result.size).to eq(2)
        expect(result.map do |n|
          n.attribute("id").value
        end).to contain_exactly("c1", "c2")
      end

      it "does not include context node" do
        ast = Moxml::XPath::Parser.parse("/root/parent/descendant::parent")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        # Should not find parent itself, only descendants named parent
        expect(result).to be_empty
      end

      it "finds all descendants at any depth" do
        ast = Moxml::XPath::Parser.parse("/root/descendant::*")
        proc = Moxml::XPath::Compiler.compile_with_cache(ast)
        result = proc.call(doc)

        # parent + 2 children + 2 grandchildren = 5
        expect(result.size).to eq(5)
      end
    end
  end

  describe "Axis + Predicate Combinations" do
    let(:book_doc) do
      xml = <<~XML
        <library>
          <book price="10" category="fiction">
            <title>Book A</title>
          </book>
          <book price="20" category="tech">
            <title>Book B</title>
          </book>
          <book price="15" category="fiction">
            <title>Book C</title>
          </book>
        </library>
      XML
      context.parse(xml)
    end

    it "combines descendant-or-self with element test" do
      ast = Moxml::XPath::Parser.parse("//book")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(book_doc)

      expect(result.size).to eq(3)
    end

    it "combines attribute axis with wildcards" do
      skip "HeadedOx limitation: Attribute wildcard (@*) not supported by XPath parser. See docs/HEADED_OX_LIMITATIONS.md"
      ast = Moxml::XPath::Parser.parse("//book/@*")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(book_doc)

      # 3 books × 2 attributes each = 6
      expect(result.size).to eq(6)
    end
  end

  describe "Real-world XPath Patterns" do
    let(:complex_doc) do
      xml = <<~XML
        <catalog>
          <section name="Programming">
            <book id="b1" price="29.99">
              <title lang="en">Ruby Programming</title>
              <author>Matz</author>
            </book>
            <book id="b2" price="39.99">
              <title lang="en">Python Programming</title>
              <author>Guido</author>
            </book>
          </section>
          <section name="Databases">
            <book id="b3" price="49.99">
              <title lang="en">PostgreSQL Essentials</title>
              <author>Expert</author>
            </book>
          </section>
        </catalog>
      XML
      context.parse(xml)
    end

    it "finds all books anywhere //book" do
      ast = Moxml::XPath::Parser.parse("//book")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(complex_doc)

      expect(result.size).to eq(3)
    end

    it "finds all titles anywhere //title" do
      ast = Moxml::XPath::Parser.parse("//title")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(complex_doc)

      expect(result.size).to eq(3)
      expect(result.map(&:text)).to include("Ruby Programming",
                                            "Python Programming", "PostgreSQL Essentials")
    end

    it "finds all price attributes //book/@price" do
      ast = Moxml::XPath::Parser.parse("//book/@price")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(complex_doc)

      expect(result.size).to eq(3)
      expect(result.map(&:value)).to contain_exactly("29.99", "39.99", "49.99")
    end

    it "combines // with specific paths //section/book" do
      ast = Moxml::XPath::Parser.parse("//section/book")
      proc = Moxml::XPath::Compiler.compile_with_cache(ast)
      result = proc.call(complex_doc)

      expect(result.size).to eq(3)
    end
  end
end
