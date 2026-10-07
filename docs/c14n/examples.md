# C14N examples

## Whole-document canonicalization

```ruby
doc = Moxml.new.parse(xml)
Moxml::C14n.canonicalize(doc)
# => "<?xml version=\"1.0\"?>\n<a b=\"1\">text</a>\n"
```

## Subset canonicalization (enveloped signature shape)

Only nodes matched by the XPath expression render — the same-document
reference pattern:

```ruby
Moxml::C14n.canonicalize_subset(doc, "//ds:SignedInfo",
                                { "ds" => "http://www.w3.org/2000/09/xmldsig#" })
```

## Canonical comparison

Testing two documents for semantic equality — whitespace, attribute
order, and prefix choice are eliminated before comparison:

```ruby
Moxml::C14n.same_canonical_form?(v1_document, v2_document)   # => true
Moxml::C14n.same_canonical_form?(fixture_xml, output_string) # => true
```

## Cross-adapter verification

A signature produced with one adapter must verify with another — the
canonical bytes are byte-identical across adapters:

```ruby
%i[leptris nokogiri rexml ox libxml].map do |adapter|
  Moxml.new(adapter).parse(xml).then { |d| Moxml::C14n.canonicalize(d) }
end.uniq.size # => 1
```

## Digest of a subtree

```ruby
signed_element.digest
# engine-delegated SHA-256 over the subtree's canonical form
```
