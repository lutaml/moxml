require_relative "../../lib/moxml"

# HeadedOx Adapter Demo
# Demonstrates Ox's fast parsing + comprehensive XPath

# Sample XML
xml = <<~XML
  <library>
    <book id="1" price="15.99" year="2020">
      <title>Programming Ruby</title>
      <author>Matz</author>
      <isbn>978-1234567890</isbn>
    </book>
    <book id="2" price="25.99" year="2021">
      <title>Programming Python</title>
      <author>Guido</author>
      <isbn>978-0987654321</isbn>
    </book>
    <book id="3" price="12.99" year="2022">
      <title>Programming JavaScript</title>
      <author>Brendan</author>
      <isbn>978-1122334455</isbn>
    </book>
  </library>
XML

# Initialize HeadedOx
context = Moxml.new(:headed_ox)
doc = context.parse(xml)

puts "=" * 60
puts "HeadedOx Demo - Comprehensive XPath on Fast Ox Parsing"
puts "=" * 60

# 1. Basic descendant queries
puts "\n1. Find all books:"
books = doc.xpath("//book")
puts "Found #{books.size} books"

# 2. Attribute selection
puts "\n2. Get all prices:"
prices = doc.xpath("//book/@price")
puts "Prices: #{prices.map(&:value).join(', ')}"

# 3. Predicates
puts "\n3. Find cheap books (< $20):"
cheap = doc.xpath("//book[@price < 20]")
cheap.each do |book|
  puts "  - #{book.xpath('title').first.text}: $#{book['price']}"
end

# 4. XPath functions
puts "\n4. XPath functions:"
puts "  Total books: #{doc.xpath('count(//book)')}"
puts "  Total price: $#{doc.xpath('sum(//book/@price)')}"
puts "  First title: #{doc.xpath('string(//book[1]/title)')}"

# 5. Complex queries
puts "\n5. Books with 'Ruby' in title:"
ruby_books = doc.xpath('//book[contains(title, "Ruby")]')
ruby_books.each { |book| puts "  - #{book.xpath('title').first.text}" }

# 6. Variable binding
puts "\n6. Using variables:"
max_price = 20
affordable = doc.xpath("//book[@price < $max]", { "max" => max_price })
puts "Books under $#{max_price}: #{affordable.size}"

puts "\n#{'=' * 60}"
puts "HeadedOx provides full XPath 1.0 support!"
puts "=" * 60
