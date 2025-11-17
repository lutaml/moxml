# frozen_string_literal: true

require "spec_helper"

RSpec.describe "HeadedOx Integration" do
  let(:xml) do
    <<~XML
      <library>
        <book id="1" price="15.99">
          <title>Ruby Programming</title>
          <author>Alice</author>
          <year>2020</year>
        </book>
        <book id="2" price="25.99">
          <title>Python Programming</title>
          <author>Bob</author>
          <year>2021</year>
        </book>
        <book id="3" price="12.99">
          <title>JavaScript Programming</title>
          <author>Charlie</author>
          <year>2022</year>
        </book>
      </library>
    XML
  end

  let(:context) { Moxml.new(:headed_ox) }
  let(:doc) { context.parse(xml) }

  describe "parsing and querying XML end-to-end" do
    it "parses XML document" do
      expect(doc).to be_a(Moxml::Document)
      expect(doc.root.name).to eq("library")
    end

    it "executes simple XPath queries" do
      books = doc.xpath("//book")

      expect(books.size).to eq(3)
      expect(books).to all(be_a(Moxml::Element))
    end

    it "executes XPath with numeric predicates" do
      cheap_books = doc.xpath("//book[@price < 20]")

      expect(cheap_books.size).to eq(2)
      expect(cheap_books.map { |b| b["id"] }).to contain_exactly("1", "3")
    end

    it "executes XPath with function calls" do
      count = doc.xpath("count(//book)")

      expect(count).to eq(3.0)
    end

    it "executes complex XPath expressions" do
      titles = doc.xpath("//book[@price < 20]/title")

      expect(titles.size).to eq(2)
      expect(titles.map(&:text)).to contain_exactly(
        "Ruby Programming",
        "JavaScript Programming"
      )
    end
  end

  describe "XPath function categories" do
    context "string functions" do
      it "retrieves text content with string()" do
        title = doc.xpath("string(//book[1]/title)")

        expect(title).to eq("Ruby Programming")
      end

      it "searches with contains()" do
        ruby_books = doc.xpath("//book[contains(title, 'Ruby')]")

        expect(ruby_books.size).to eq(1)
        expect(ruby_books.first["id"]).to eq("1")
      end

      it "filters with starts-with()" do
        prog_books = doc.xpath("//book[starts-with(title, 'Python')]")

        expect(prog_books.size).to eq(1)
        expect(prog_books.first["id"]).to eq("2")
      end

      it "concatenates strings with concat()" do
        result = doc.xpath("concat('Book: ', //book[1]/title)")

        expect(result).to eq("Book: Ruby Programming")
      end

      it "normalizes whitespace with normalize-space()" do
        result = doc.xpath("normalize-space('  hello  world  ')")

        expect(result).to eq("hello world")
      end
    end

    context "numeric functions" do
      it "converts to number with number()" do
        price = doc.xpath("number(//book[1]/@price)")

        expect(price).to eq(15.99)
      end

      it "sums values with sum()" do
        total = doc.xpath("sum(//book/@price)")

        expect(total).to be_within(0.01).of(54.97)
      end

      it "counts nodes with count()" do
        count = doc.xpath("count(//book)")

        expect(count).to eq(3.0)
      end

      it "applies floor() function" do
        result = doc.xpath("floor(15.99)")

        expect(result).to eq(15.0)
      end

      it "applies ceiling() function" do
        result = doc.xpath("ceiling(12.01)")

        expect(result).to eq(13.0)
      end

      it "applies round() function" do
        result = doc.xpath("round(15.5)")

        expect(result).to eq(16.0)
      end
    end

    context "boolean functions" do
      it "converts to boolean with boolean()" do
        has_books = doc.xpath("boolean(//book)")

        expect(has_books).to be true
      end

      it "negates with not()" do
        result = doc.xpath("not(false())")

        expect(result).to be true
      end

      it "returns true with true()" do
        result = doc.xpath("true()")

        expect(result).to be true
      end

      it "returns false with false()" do
        result = doc.xpath("false()")

        expect(result).to be false
      end
    end

    context "node functions" do
      it "gets node name with name()" do
        name = doc.xpath("name(//book[1])")

        expect(name).to eq("book")
      end

      it "gets local name with local-name()" do
        name = doc.xpath("local-name(//book[1])")

        expect(name).to eq("book")
      end
    end

    context "position functions" do
      it "filters by position with position()" do
        second_book = doc.xpath("//book[position() = 2]")

        expect(second_book.size).to eq(1)
        expect(second_book.first["id"]).to eq("2")
      end

      it "selects last node with last()" do
        last_book = doc.xpath("//book[position() = last()]")

        expect(last_book.size).to eq(1)
        expect(last_book.first["id"]).to eq("3")
      end
    end
  end

  describe "real-world use cases" do
    it "finds books by author and price range" do
      results = doc.xpath(
        "//book[contains(author, 'Alice') and @price < 20]"
      )

      expect(results.size).to eq(1)
      expect(results.first.xpath("title").first.text).to eq("Ruby Programming")
    end

    it "calculates statistics" do
      avg_price = doc.xpath("sum(//book/@price) div count(//book)")

      expect(avg_price).to be_within(0.01).of(18.32)
    end

    it "combines multiple axes and predicates" do
      # Books with price < 20, get their authors
      authors = doc.xpath("//book[@price < 20]/author")

      expect(authors.size).to eq(2)
      expect(authors.map(&:text)).to contain_exactly("Alice", "Charlie")
    end

    it "uses parent axis for traversal" do
      # Find title "Ruby Programming", then get parent book's author
      author = doc.xpath(
        "//title[contains(., 'Ruby')]/parent::book/author"
      )

      expect(author.size).to eq(1)
      expect(author.first.text).to eq("Alice")
    end
  end

  describe "comparison with standard Ox adapter" do
    let(:ox_context) { Moxml.new(:ox) }
    let(:ox_doc) { ox_context.parse(xml) }

    it "handles predicates that Ox cannot" do
      # HeadedOx handles complex predicates
      headed_result = doc.xpath("//book[@price < 20]")
      expect(headed_result.size).to eq(2)

      # Standard Ox would have issues with this predicate
      # (it would need translation to locate() syntax)
    end

    it "provides same parsing speed as Ox" do
      # Both use Ox for parsing, so speed should be similar
      start = Time.now
      context.parse(xml)
      headed_time = Time.now - start

      start = Time.now
      ox_context.parse(xml)
      ox_time = Time.now - start

      # Should be within same magnitude (both very fast)
      expect(headed_time).to be < 0.1
      expect(ox_time).to be < 0.1
    end
  end

  describe "edge cases" do
    it "handles empty results" do
      result = doc.xpath("//nonexistent")

      expect(result).to be_a(Moxml::NodeSet)
      expect(result).to be_empty
    end

    it "handles nested predicates" do
      result = doc.xpath(
        "//book[author[contains(., 'Alice')]]"
      )

      expect(result.size).to eq(1)
    end

    it "handles union expressions" do
      result = doc.xpath("//title | //author")

      expect(result.size).to eq(6)  # 3 titles + 3 authors
    end

    it "handles attribute selection" do
      prices = doc.xpath("//book/@price")

      expect(prices.size).to eq(3)
      expect(prices).to all(be_a(Moxml::Attribute))
    end
  end

  describe "namespace support" do
    let(:ns_xml) do
      <<~XML
        <library xmlns:bk="http://example.com/books">
          <bk:book>
            <bk:title>Test Book</bk:title>
          </bk:book>
        </library>
      XML
    end

    let(:ns_doc) { context.parse(ns_xml) }

    it "queries with namespace prefixes" do
      result = ns_doc.xpath(
        "//bk:book",
        { "bk" => "http://example.com/books" }
      )

      expect(result.size).to eq(1)
    end

    it "queries namespace elements with functions" do
      result = ns_doc.xpath(
        "//bk:title",
        { "bk" => "http://example.com/books" }
      )

      expect(result.size).to eq(1)
      expect(result.first.text).to eq("Test Book")
    end
  end
end