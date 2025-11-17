# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::XPath::Compiler do
  let(:context) { Moxml.new(:nokogiri) }
  let(:xml) do
    <<~XML
      <root>
        <child id="1">text1</child>
        <child id="2">text2</child>
        <other>other text</other>
      </root>
    XML
  end
  let(:doc) { context.parse(xml) }

  describe ".compile_with_cache" do
    it "compiles a simple path expression" do
      ast = Moxml::XPath::Parser.parse("/root")
      proc = described_class.compile_with_cache(ast)

      expect(proc).to be_a(Proc)
    end

    it "caches compiled expressions" do
      ast = Moxml::XPath::Parser.parse("/root")
      proc1 = described_class.compile_with_cache(ast)
      proc2 = described_class.compile_with_cache(ast)

      expect(proc1).to equal(proc2)
    end

    it "uses different cache keys for different namespaces" do
      ast = Moxml::XPath::Parser.parse("/root")
      proc1 = described_class.compile_with_cache(ast,
                                                 namespaces: { "x" => "http://example.com" })
      proc2 = described_class.compile_with_cache(ast,
                                                 namespaces: { "y" => "http://other.com" })

      expect(proc1).not_to equal(proc2)
    end
  end

  describe "Basic compilation" do
    it "compiles and executes /root" do
      ast = Moxml::XPath::Parser.parse("/root")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(1)
      expect(result.first.name).to eq("root")
    end

    it "compiles and executes /root/child" do
      ast = Moxml::XPath::Parser.parse("/root/child")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map(&:name)).to eq(["child", "child"])
    end

    it "compiles and executes /root/other" do
      ast = Moxml::XPath::Parser.parse("/root/other")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(1)
      expect(result.first.name).to eq("other")
    end
  end

  describe "Axis: child" do
    it "selects direct children" do
      ast = Moxml::XPath::Parser.parse("/root/child")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(2)
      expect(result.map(&:name)).to all(eq("child"))
    end

    it "returns empty set when no children match" do
      ast = Moxml::XPath::Parser.parse("/root/nonexistent")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_empty
    end
  end

  describe "Axis: self" do
    it "selects the node itself" do
      ast = Moxml::XPath::Parser.parse("/root/self::root")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(1)
      expect(result.first.name).to eq("root")
    end
  end

  describe "Axis: parent" do
    it "selects parent node" do
      ast = Moxml::XPath::Parser.parse("/root/child/parent::root")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(2) # Two child elements have same parent
      expect(result.first.name).to eq("root")
    end
  end

  describe "Axis: descendant-or-self (//)" do
    let(:nested_xml) do
      <<~XML
        <root>
          <book price="10">
            <title>Programming Ruby</title>
            <author>Matz</author>
          </book>
          <book price="20">
            <title>Programming Python</title>
            <author>Guido</author>
          </book>
        </root>
      XML
    end
    let(:nested_doc) { context.parse(nested_xml) }

    it "finds all descendants with //" do
      ast = Moxml::XPath::Parser.parse("//title")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(nested_doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map(&:text)).to contain_exactly("Programming Ruby",
                                                    "Programming Python")
    end

    it "finds nested elements" do
      ast = Moxml::XPath::Parser.parse("//author")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(nested_doc)

      expect(result.size).to eq(2)
      expect(result.map(&:text)).to contain_exactly("Matz", "Guido")
    end

    it "works with wildcards" do
      skip "HeadedOx limitation: Wildcard count differs due to Ox's DOM structure. See docs/HEADED_OX_LIMITATIONS.md"
      ast = Moxml::XPath::Parser.parse("//*")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(nested_doc)

      # Should find root, 2 books, 2 titles, 2 authors = 7 elements
      expect(result.size).to be >= 7
    end
  end

  describe "Axis: attribute (@)" do
    let(:attr_xml) do
      <<~XML
        <root>
          <book price="10" isbn="123">
            <title lang="en">Book 1</title>
          </book>
          <book price="20" isbn="456">
            <title lang="fr">Book 2</title>
          </book>
        </root>
      XML
    end
    let(:attr_doc) { context.parse(attr_xml) }

    it "selects attributes with @" do
      ast = Moxml::XPath::Parser.parse("/root/book/@price")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(attr_doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map(&:value)).to contain_exactly("10", "20")
    end

    it "works with wildcards" do
      skip "HeadedOx limitation: Attribute wildcard (@*) not supported by XPath parser. See docs/HEADED_OX_LIMITATIONS.md"
      ast = Moxml::XPath::Parser.parse("/root/book/@*")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(attr_doc)

      # Each book has 2 attributes (price, isbn) = 4 total
      expect(result.size).to eq(4)
    end

    it "selects nested element attributes" do
      ast = Moxml::XPath::Parser.parse("/root/book/title/@lang")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(attr_doc)

      expect(result.size).to eq(2)
      expect(result.map(&:value)).to contain_exactly("en", "fr")
    end

    it "returns empty when no attributes match" do
      ast = Moxml::XPath::Parser.parse("/root/book/@nonexistent")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(attr_doc)

      expect(result).to be_empty
    end
  end

  describe "Axis: descendant" do
    let(:desc_xml) do
      <<~XML
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
    end
    let(:desc_doc) { context.parse(desc_xml) }

    it "finds all descendants without self" do
      ast = Moxml::XPath::Parser.parse("/root/descendant::grandchild")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(desc_doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(2)
      expect(result.map do |n|
        n.attribute("id")&.value
      end).to contain_exactly("g1", "g2")
    end

    it "does not include the context node itself" do
      ast = Moxml::XPath::Parser.parse("/root/parent/descendant::parent")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(desc_doc)

      # Should not find parent itself, only descendants named parent (none)
      expect(result).to be_empty
    end
  end

  describe "Node tests" do
    it "matches element names" do
      ast = Moxml::XPath::Parser.parse("/root/child")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.map(&:name)).to all(eq("child"))
    end

    it "handles wildcard" do
      ast = Moxml::XPath::Parser.parse("/root/*")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result.size).to eq(3) # 2 child + 1 other
    end

    it "matches case-insensitively" do
      xml_mixed = "<ROOT><Child>text</Child></ROOT>"
      doc_mixed = context.parse(xml_mixed)

      ast = Moxml::XPath::Parser.parse("/root/child")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc_mixed)

      expect(result.size).to eq(1)
    end
  end

  describe "Literals" do
    it "compiles string literals" do
      ast = Moxml::XPath::AST::Node.string("hello")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq("hello")
    end

    it "compiles number literals" do
      ast = Moxml::XPath::AST::Node.number(42)
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(42.0)
    end

    it "compiles float literals" do
      ast = Moxml::XPath::AST::Node.number(3.14)
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(3.14)
    end
  end

  describe "Special nodes" do
    it "handles current node (.)" do
      ast = Moxml::XPath::Parser.parse(".")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to eq(doc)
    end

    it "handles parent node (..)" do
      # Get a child first
      ast = Moxml::XPath::Parser.parse("/root/child")
      proc = described_class.compile_with_cache(ast)
      children = proc.call(doc)

      # Now get parent from child
      parent_ast = Moxml::XPath::Parser.parse("..")
      parent_proc = described_class.compile_with_cache(parent_ast)
      result = parent_proc.call(children.first)

      expect(result.name).to eq("root")
    end
  end

  describe "Complex paths" do
    it "handles multi-step paths" do
      xml_nested = <<~XML
        <root>
          <level1>
            <level2>
              <target>found</target>
            </level2>
          </level1>
        </root>
      XML
      doc_nested = context.parse(xml_nested)

      ast = Moxml::XPath::Parser.parse("/root/level1/level2/target")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc_nested)

      expect(result.size).to eq(1)
      expect(result.first.name).to eq("target")
    end

    it "handles paths that return no results" do
      ast = Moxml::XPath::Parser.parse("/root/nonexistent/child")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_empty
    end
  end

  describe "Root node handling" do
    it "selects document root with /" do
      ast = Moxml::XPath::Parser.parse("/")
      proc = described_class.compile_with_cache(ast)
      result = proc.call(doc)

      expect(result).to be_a(Moxml::NodeSet)
      expect(result.size).to eq(1)
      # Root should be the document or root element
    end
  end

  describe "Error handling" do
    it "handles malformed AST gracefully" do
      # Create an AST with an unknown type
      ast = Moxml::XPath::AST::Node.new(:unknown_type)

      expect do
        described_class.compile_with_cache(ast)
      end.to raise_error(NoMethodError, /on_unknown_type/)
    end
  end

  describe "Cache behavior" do
    it "limits cache size" do
      # Generate many different expressions
      cache = Moxml::XPath::Cache.new(5)
      compiler_class = Class.new(described_class) do
        const_set(:CACHE, cache)
      end

      10.times do |i|
        ast = Moxml::XPath::Parser.parse("/root/child#{i}")
        compiler_class.compile_with_cache(ast)
      end

      expect(cache.size).to be <= 5
    end
  end
end
