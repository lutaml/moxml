# frozen_string_literal: true

require "spec_helper"

RSpec.describe Moxml::SAX do
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <library>
        <book id="1" category="programming">
          <title>Ruby Programming</title>
          <author>Jane Smith</author>
          <price>29.99</price>
        </book>
        <book id="2" category="fiction">
          <title>The Great Novel</title>
          <author>John Doe</author>
          <price>19.99</price>
        </book>
      </library>
    XML
  end

  describe "Handler" do
    it "provides base event methods" do
      handler = Moxml::SAX::Handler.new
      expect(handler).to respond_to(:on_start_document)
      expect(handler).to respond_to(:on_end_document)
      expect(handler).to respond_to(:on_start_element)
      expect(handler).to respond_to(:on_end_element)
      expect(handler).to respond_to(:on_characters)
      expect(handler).to respond_to(:on_cdata)
      expect(handler).to respond_to(:on_comment)
      expect(handler).to respond_to(:on_processing_instruction)
      expect(handler).to respond_to(:on_error)
      expect(handler).to respond_to(:on_warning)
    end
  end

  describe "ElementHandler" do
    it "tracks element stack" do
      handler = Moxml::SAX::ElementHandler.new

      handler.on_start_element("library", {}, {})
      expect(handler.element_stack).to eq(["library"])
      expect(handler.current_element).to eq("library")

      handler.on_start_element("book", { "id" => "1" }, {})
      expect(handler.element_stack).to eq(["library", "book"])
      expect(handler.current_element).to eq("book")
      expect(handler.parent_element).to eq("library")

      handler.on_end_element("book")
      expect(handler.element_stack).to eq(["library"])

      handler.on_end_element("library")
      expect(handler.element_stack).to be_empty
    end

    it "provides path matching" do
      handler = Moxml::SAX::ElementHandler.new

      handler.on_start_element("library", {}, {})
      handler.on_start_element("book", {}, {})
      handler.on_start_element("title", {}, {})

      expect(handler.path_matches?("/library/book/title")).to be true
      expect(handler.path_matches?(%r{book/title$})).to be true
      expect(handler.path_matches?("/library/author")).to be false

      expect(handler.path_string).to eq("/library/book/title")
      expect(handler.depth).to eq(3)
    end

    it "checks element presence" do
      handler = Moxml::SAX::ElementHandler.new

      handler.on_start_element("library", {}, {})
      expect(handler.in_element?("library")).to be true
      expect(handler.in_element?("book")).to be false

      handler.on_start_element("book", {}, {})
      expect(handler.in_element?("library")).to be true
      expect(handler.in_element?("book")).to be true
    end
  end

  describe "BlockHandler" do
    it "supports DSL-style handler definition" do
      elements = []

      handler = Moxml::SAX::BlockHandler.new do
        start_element { |name, attrs| elements << name }
      end

      handler.on_start_element("book", {}, {})
      handler.on_start_element("title", {}, {})

      expect(elements).to eq(["book", "title"])
    end

    it "supports multiple event handlers" do
      events = []

      handler = Moxml::SAX::BlockHandler.new do
        start_document { events << :start_doc }
        start_element { |name| events << [:start, name] }
        end_element { |name| events << [:end, name] }
        characters { |text| events << [:text, text.strip] unless text.strip.empty? }
        end_document { events << :end_doc }
      end

      handler.on_start_document
      handler.on_start_element("book", {}, {})
      handler.on_characters("Title")
      handler.on_end_element("book")
      handler.on_end_document

      expect(events).to eq([
        :start_doc,
        [:start, "book"],
        [:text, "Title"],
        [:end, "book"],
        :end_doc
      ])
    end
  end

  describe "SAX parsing with Nokogiri adapter", :adapter => :nokogiri do
    let(:context) { Moxml.new(:nokogiri) }

    it "parses with class-based handler" do
      # Custom handler to extract book data
      class BookExtractor < Moxml::SAX::ElementHandler
        attr_reader :books

        def initialize
          super
          @books = []
          @current_book = nil
          @current_text = ""
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          super
          case name
          when "book"
            @current_book = { id: attributes["id"], category: attributes["category"] }
          when "title", "author", "price"
            @current_text = "".dup  # Use dup to create mutable string
          end
        end

        def on_characters(text)
          @current_text << text if @current_book && !@current_text.frozen?
        end

        def on_end_element(name)
          case name
          when "title"
            @current_book[:title] = @current_text.strip if @current_book
          when "author"
            @current_book[:author] = @current_text.strip if @current_book
          when "price"
            @current_book[:price] = @current_text.strip.to_f if @current_book
          when "book"
            @books << @current_book if @current_book
            @current_book = nil
          end
          super
        end
      end

      handler = BookExtractor.new
      context.sax_parse(xml, handler)

      expect(handler.books.length).to eq(2)

      expect(handler.books[0]).to include(
        id: "1",
        category: "programming",
        title: "Ruby Programming",
        author: "Jane Smith",
        price: 29.99
      )

      expect(handler.books[1]).to include(
        id: "2",
        category: "fiction",
        title: "The Great Novel",
        author: "John Doe",
        price: 19.99
      )
    end

    it "parses with block-based handler" do
      books = []
      current_book = nil
      current_field = nil
      current_text = ""

      context.sax_parse(xml) do
        start_element do |name, attrs|
          case name
          when "book"
            current_book = { id: attrs["id"] }
          when "title", "author", "price"
            current_field = name
            current_text = "".dup  # Use dup to create mutable string
          end
        end

        characters do |text|
          current_text << text if current_field && !current_text.frozen?
        end

        end_element do |name|
          case name
          when "title", "author"
            current_book[current_field.to_sym] = current_text.strip if current_book
            current_field = nil
          when "price"
            current_book[current_field.to_sym] = current_text.strip.to_f if current_book
            current_field = nil
          when "book"
            books << current_book if current_book
            current_book = nil
          end
        end
      end

      expect(books.length).to eq(2)
      expect(books[0][:title]).to eq("Ruby Programming")
      expect(books[1][:title]).to eq("The Great Novel")
    end

    it "handles errors gracefully" do
      invalid_xml = "<book><title>Unclosed"

      handler = Moxml::SAX::Handler.new

      # Override error handler to catch it
      def handler.on_error(error)
        @error_caught = true
        @error_message = error.message
      end

      def handler.error_caught?
        @error_caught
      end

      def handler.error_message
        @error_message
      end

      context.sax_parse(invalid_xml, handler)

      expect(handler.error_caught?).to be true
      expect(handler.error_message).to match(/Premature end of data|unclosed token/i)
    end
  end

  describe "SAX parsing with Ox adapter", :adapter => :ox do
    let(:context) { Moxml.new(:ox) }

    it "parses with class-based handler" do
      # Reuse BookExtractor from Nokogiri tests
      class BookExtractorOx < Moxml::SAX::ElementHandler
        attr_reader :books

        def initialize
          super
          @books = []
          @current_book = nil
          @current_text = ""
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          super
          case name
          when "book"
            @current_book = { id: attributes["id"], category: attributes["category"] }
          when "title", "author", "price"
            @current_text = "".dup
          end
        end

        def on_characters(text)
          @current_text << text if @current_book && !@current_text.frozen?
        end

        def on_end_element(name)
          case name
          when "title"
            @current_book[:title] = @current_text.strip if @current_book
          when "author"
            @current_book[:author] = @current_text.strip if @current_book
          when "price"
            @current_book[:price] = @current_text.strip.to_f if @current_book
          when "book"
            @books << @current_book if @current_book
            @current_book = nil
          end
          super
        end
      end

      handler = BookExtractorOx.new
      context.sax_parse(xml, handler)

      expect(handler.books.length).to eq(2)

      expect(handler.books[0]).to include(
        id: "1",
        category: "programming",
        title: "Ruby Programming",
        author: "Jane Smith",
        price: 29.99
      )

      expect(handler.books[1]).to include(
        id: "2",
        category: "fiction",
        title: "The Great Novel",
        author: "John Doe",
        price: 19.99
      )
    end

    it "parses with block-based handler" do
      # Use a result collector that's accessible from block context
      results = { books: [], current_book: nil, current_field: nil, current_text: "".dup }

      context.sax_parse(xml) do
        start_element do |name, attrs|
          case name
          when "book"
            results[:current_book] = { id: attrs["id"] }
          when "title", "author", "price"
            results[:current_field] = name
            results[:current_text] = "".dup
          end
        end

        characters do |text|
          if results[:current_field] && !results[:current_text].frozen?
            results[:current_text] << text
          end
        end

        end_element do |name|
          case name
          when "title", "author"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip
            end
            results[:current_field] = nil
          when "price"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip.to_f
            end
            results[:current_field] = nil
          when "book"
            results[:books] << results[:current_book] if results[:current_book]
            results[:current_book] = nil
          end
        end
      end

      expect(results[:books].length).to eq(2)
      expect(results[:books][0][:title]).to eq("Ruby Programming")
      expect(results[:books][1][:title]).to eq("The Great Novel")
    end

    it "handles errors gracefully" do
      invalid_xml = "<book><title>Unclosed"

      handler = Moxml::SAX::Handler.new

      # Override error handler to catch it
      def handler.on_error(error)
        @error_caught = true
        @error_message = error.message
      end

      def handler.error_caught?
        @error_caught
      end

      def handler.error_message
        @error_message
      end

      context.sax_parse(invalid_xml, handler)

      expect(handler.error_caught?).to be true
      expect(handler.error_message).to match(/invalid|unclosed|premature|mismatch|not closed/i)
    end

    it "documents CDATA limitation" do
      # Ox SAX does not have separate CDATA events
      # All CDATA content is delivered as text() events
      skip "Ox SAX does not support separate CDATA events"

      xml_with_cdata = '<root><![CDATA[special content]]></root>'

      cdata_found = false
      context.sax_parse(xml_with_cdata) do
        cdata { |text| cdata_found = true }
      end

      # This will fail because Ox doesn't support separate CDATA events
      expect(cdata_found).to be true
    end

    it "documents comment limitation" do
      # Ox SAX does not have separate comment events
      skip "Ox SAX does not support separate comment events"

      xml_with_comment = '<root><!-- comment --><data>content</data></root>'

      comment_found = false
      context.sax_parse(xml_with_comment) do
        comment { |text| comment_found = true }
      end

      # This will fail because Ox doesn't support comment events
      expect(comment_found).to be true
    end

    it "documents processing instruction limitation" do
      # Ox SAX does not have separate PI events
      skip "Ox SAX does not support separate processing instruction events"

      xml_with_pi = '<?xml-stylesheet type="text/xsl" href="style.xsl"?><root/>'

      pi_found = false
      context.sax_parse(xml_with_pi) do
        processing_instruction { |target, data| pi_found = true }
      end

      # This will fail because Ox doesn't support PI events
      expect(pi_found).to be true
    end
  end

  describe "SAX parsing with REXML adapter", :adapter => :rexml do
    let(:context) { Moxml.new(:rexml) }

    it "parses with class-based handler" do
      # Reuse BookExtractor pattern
      class BookExtractorRexml < Moxml::SAX::ElementHandler
        attr_reader :books

        def initialize
          super
          @books = []
          @current_book = nil
          @current_text = ""
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          super
          case name
          when "book"
            @current_book = { id: attributes["id"], category: attributes["category"] }
          when "title", "author", "price"
            @current_text = "".dup
          end
        end

        def on_characters(text)
          @current_text << text if @current_book && !@current_text.frozen?
        end

        def on_end_element(name)
          case name
          when "title"
            @current_book[:title] = @current_text.strip if @current_book
          when "author"
            @current_book[:author] = @current_text.strip if @current_book
          when "price"
            @current_book[:price] = @current_text.strip.to_f if @current_book
          when "book"
            @books << @current_book if @current_book
            @current_book = nil
          end
          super
        end
      end

      handler = BookExtractorRexml.new
      context.sax_parse(xml, handler)

      expect(handler.books.length).to eq(2)

      expect(handler.books[0]).to include(
        id: "1",
        category: "programming",
        title: "Ruby Programming",
        author: "Jane Smith",
        price: 29.99
      )

      expect(handler.books[1]).to include(
        id: "2",
        category: "fiction",
        title: "The Great Novel",
        author: "John Doe",
        price: 19.99
      )
    end

    it "parses with block-based handler" do
      results = { books: [], current_book: nil, current_field: nil, current_text: "".dup }

      context.sax_parse(xml) do
        start_element do |name, attrs|
          case name
          when "book"
            results[:current_book] = { id: attrs["id"] }
          when "title", "author", "price"
            results[:current_field] = name
            results[:current_text] = "".dup
          end
        end

        characters do |text|
          if results[:current_field] && !results[:current_text].frozen?
            results[:current_text] << text
          end
        end

        end_element do |name|
          case name
          when "title", "author"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip
            end
            results[:current_field] = nil
          when "price"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip.to_f
            end
            results[:current_field] = nil
          when "book"
            results[:books] << results[:current_book] if results[:current_book]
            results[:current_book] = nil
          end
        end
      end

      expect(results[:books].length).to eq(2)
      expect(results[:books][0][:title]).to eq("Ruby Programming")
      expect(results[:books][1][:title]).to eq("The Great Novel")
    end

    it "handles errors gracefully" do
      invalid_xml = "<book><title>Unclosed"

      handler = Moxml::SAX::Handler.new

      # Override error handler to catch it
      def handler.on_error(error)
        @error_caught = true
        @error_message = error.message
      end

      def handler.error_caught?
        @error_caught
      end

      def handler.error_message
        @error_message
      end

      context.sax_parse(invalid_xml, handler)

      expect(handler.error_caught?).to be true
      expect(handler.error_message).to match(/missing|end tag|unclosed/i)
    end
  end

  describe "SAX parsing with Oga adapter", :adapter => :oga do
    let(:context) { Moxml.new(:oga) }

    it "parses with class-based handler" do
      # Reuse BookExtractor pattern
      class BookExtractorOga < Moxml::SAX::ElementHandler
        attr_reader :books

        def initialize
          super
          @books = []
          @current_book = nil
          @current_text = ""
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          super
          case name
          when "book"
            @current_book = { id: attributes["id"], category: attributes["category"] }
          when "title", "author", "price"
            @current_text = "".dup
          end
        end

        def on_characters(text)
          @current_text << text if @current_book && !@current_text.frozen?
        end

        def on_end_element(name)
          case name
          when "title"
            @current_book[:title] = @current_text.strip if @current_book
          when "author"
            @current_book[:author] = @current_text.strip if @current_book
          when "price"
            @current_book[:price] = @current_text.strip.to_f if @current_book
          when "book"
            @books << @current_book if @current_book
            @current_book = nil
          end
          super
        end
      end

      handler = BookExtractorOga.new
      context.sax_parse(xml, handler)

      expect(handler.books.length).to eq(2)

      expect(handler.books[0]).to include(
        id: "1",
        category: "programming",
        title: "Ruby Programming",
        author: "Jane Smith",
        price: 29.99
      )

      expect(handler.books[1]).to include(
        id: "2",
        category: "fiction",
        title: "The Great Novel",
        author: "John Doe",
        price: 19.99
      )
    end

    it "parses with block-based handler" do
      results = { books: [], current_book: nil, current_field: nil, current_text: "".dup }

      context.sax_parse(xml) do
        start_element do |name, attrs|
          case name
          when "book"
            results[:current_book] = { id: attrs["id"] }
          when "title", "author", "price"
            results[:current_field] = name
            results[:current_text] = "".dup
          end
        end

        characters do |text|
          if results[:current_field] && !results[:current_text].frozen?
            results[:current_text] << text
          end
        end

        end_element do |name|
          case name
          when "title", "author"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip
            end
            results[:current_field] = nil
          when "price"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip.to_f
            end
            results[:current_field] = nil
          when "book"
            results[:books] << results[:current_book] if results[:current_book]
            results[:current_book] = nil
          end
        end
      end

      expect(results[:books].length).to eq(2)
      expect(results[:books][0][:title]).to eq("Ruby Programming")
      expect(results[:books][1][:title]).to eq("The Great Novel")
    end

    it "handles errors gracefully" do
      skip "Oga SAX parser may be more lenient with malformed XML"

      invalid_xml = "<book><title>Unclosed"

      handler = Moxml::SAX::Handler.new

      # Override error handler to catch it
      def handler.on_error(error)
        @error_caught = true
        @error_message = error.message
      end

      def handler.error_caught?
        @error_caught
      end

      def handler.error_message
        @error_message
      end

      context.sax_parse(invalid_xml, handler)

      expect(handler.error_caught?).to be true
      expect(handler.error_message).to match(/unexpected|invalid|unclosed/i)
    end
  end

  describe "SAX parsing with LibXML adapter", :adapter => :libxml do
    let(:context) { Moxml.new(:libxml) }

    it "parses with class-based handler" do
      # Reuse BookExtractor pattern
      class BookExtractorLibxml < Moxml::SAX::ElementHandler
        attr_reader :books

        def initialize
          super
          @books = []
          @current_book = nil
          @current_text = ""
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          super
          case name
          when "book"
            @current_book = { id: attributes["id"], category: attributes["category"] }
          when "title", "author", "price"
            @current_text = "".dup
          end
        end

        def on_characters(text)
          @current_text << text if @current_book && !@current_text.frozen?
        end

        def on_end_element(name)
          case name
          when "title"
            @current_book[:title] = @current_text.strip if @current_book
          when "author"
            @current_book[:author] = @current_text.strip if @current_book
          when "price"
            @current_book[:price] = @current_text.strip.to_f if @current_book
          when "book"
            @books << @current_book if @current_book
            @current_book = nil
          end
          super
        end
      end

      handler = BookExtractorLibxml.new
      context.sax_parse(xml, handler)

      expect(handler.books.length).to eq(2)

      expect(handler.books[0]).to include(
        id: "1",
        category: "programming",
        title: "Ruby Programming",
        author: "Jane Smith",
        price: 29.99
      )

      expect(handler.books[1]).to include(
        id: "2",
        category: "fiction",
        title: "The Great Novel",
        author: "John Doe",
        price: 19.99
      )
    end

    it "parses with block-based handler" do
      results = { books: [], current_book: nil, current_field: nil, current_text: "".dup }

      context.sax_parse(xml) do
        start_element do |name, attrs|
          case name
          when "book"
            results[:current_book] = { id: attrs["id"] }
          when "title", "author", "price"
            results[:current_field] = name
            results[:current_text] = "".dup
          end
        end

        characters do |text|
          if results[:current_field] && !results[:current_text].frozen?
            results[:current_text] << text
          end
        end

        end_element do |name|
          case name
          when "title", "author"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip
            end
            results[:current_field] = nil
          when "price"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip.to_f
            end
            results[:current_field] = nil
          when "book"
            results[:books] << results[:current_book] if results[:current_book]
            results[:current_book] = nil
          end
        end
      end

      expect(results[:books].length).to eq(2)
      expect(results[:books][0][:title]).to eq("Ruby Programming")
      expect(results[:books][1][:title]).to eq("The Great Novel")
    end

    it "handles errors gracefully" do
      invalid_xml = "<book><title>Unclosed"

      handler = Moxml::SAX::Handler.new

      # Override error handler to catch it
      def handler.on_error(error)
        @error_caught = true
        @error_message = error.message
      end

      def handler.error_caught?
        @error_caught
      end

      def handler.error_message
        @error_message
      end

      context.sax_parse(invalid_xml, handler)

      expect(handler.error_caught?).to be true
      expect(handler.error_message).to match(/error|missing|unclosed|premature/i)
    end
  end

  describe "SAX parsing with HeadedOx adapter", :adapter => :headed_ox do
    let(:context) { Moxml.new(:headed_ox) }

    it "parses with class-based handler" do
      # Reuse BookExtractor pattern
      class BookExtractorHeadedOx < Moxml::SAX::ElementHandler
        attr_reader :books

        def initialize
          super
          @books = []
          @current_book = nil
          @current_text = ""
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          super
          case name
          when "book"
            @current_book = { id: attributes["id"], category: attributes["category"] }
          when "title", "author", "price"
            @current_text = "".dup
          end
        end

        def on_characters(text)
          @current_text << text if @current_book && !@current_text.frozen?
        end

        def on_end_element(name)
          case name
          when "title"
            @current_book[:title] = @current_text.strip if @current_book
          when "author"
            @current_book[:author] = @current_text.strip if @current_book
          when "price"
            @current_book[:price] = @current_text.strip.to_f if @current_book
          when "book"
            @books << @current_book if @current_book
            @current_book = nil
          end
          super
        end
      end

      handler = BookExtractorHeadedOx.new
      context.sax_parse(xml, handler)

      expect(handler.books.length).to eq(2)

      expect(handler.books[0]).to include(
        id: "1",
        category: "programming",
        title: "Ruby Programming",
        author: "Jane Smith",
        price: 29.99
      )

      expect(handler.books[1]).to include(
        id: "2",
        category: "fiction",
        title: "The Great Novel",
        author: "John Doe",
        price: 19.99
      )
    end

    it "parses with block-based handler" do
      results = { books: [], current_book: nil, current_field: nil, current_text: "".dup }

      context.sax_parse(xml) do
        start_element do |name, attrs|
          case name
          when "book"
            results[:current_book] = { id: attrs["id"] }
          when "title", "author", "price"
            results[:current_field] = name
            results[:current_text] = "".dup
          end
        end

        characters do |text|
          if results[:current_field] && !results[:current_text].frozen?
            results[:current_text] << text
          end
        end

        end_element do |name|
          case name
          when "title", "author"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip
            end
            results[:current_field] = nil
          when "price"
            if results[:current_book] && results[:current_field]
              results[:current_book][results[:current_field].to_sym] = results[:current_text].strip.to_f
            end
            results[:current_field] = nil
          when "book"
            results[:books] << results[:current_book] if results[:current_book]
            results[:current_book] = nil
          end
        end
      end

      expect(results[:books].length).to eq(2)
      expect(results[:books][0][:title]).to eq("Ruby Programming")
      expect(results[:books][1][:title]).to eq("The Great Novel")
    end

    it "handles errors gracefully" do
      invalid_xml = "<book><title>Unclosed"

      handler = Moxml::SAX::Handler.new

      # Override error handler to catch it
      def handler.on_error(error)
        @error_caught = true
        @error_message = error.message
      end

      def handler.error_caught?
        @error_caught
      end

      def handler.error_message
        @error_message
      end

      context.sax_parse(invalid_xml, handler)

      expect(handler.error_caught?).to be true
      expect(handler.error_message).to match(/invalid|unclosed|premature|mismatch|not closed/i)
    end

    it "documents CDATA limitation (inherited from Ox)" do
      # HeadedOx inherits Ox's SAX implementation, which does not have separate CDATA events
      skip "HeadedOx SAX (inherited from Ox) does not support separate CDATA events"

      xml_with_cdata = '<root><![CDATA[special content]]></root>'

      cdata_found = false
      context.sax_parse(xml_with_cdata) do
        cdata { |text| cdata_found = true }
      end

      expect(cdata_found).to be true
    end

    it "documents comment limitation (inherited from Ox)" do
      # HeadedOx inherits Ox's SAX implementation, which does not have separate comment events
      skip "HeadedOx SAX (inherited from Ox) does not support separate comment events"

      xml_with_comment = '<root><!-- comment --><data>content</data></root>'

      comment_found = false
      context.sax_parse(xml_with_comment) do
        comment { |text| comment_found = true }
      end

      expect(comment_found).to be true
    end

    it "documents processing instruction limitation (inherited from Ox)" do
      # HeadedOx inherits Ox's SAX implementation, which does not have separate PI events
      skip "HeadedOx SAX (inherited from Ox) does not support separate processing instruction events"

      xml_with_pi = '<?xml-stylesheet type="text/xsl" href="style.xsl"?><root/>'

      pi_found = false
      context.sax_parse(xml_with_pi) do
        processing_instruction { |target, data| pi_found = true }
      end

      expect(pi_found).to be true
    end
  end
end