# Examples

Runnable examples live in `examples/signature/`. Run with:

```bash
bundle exec ruby examples/signature/enveloped_rsa.rb
bundle exec ruby examples/signature/hmac.rb
bundle exec ruby examples/signature/auto_key_extraction.rb
```

## Minimal enveloped RSA-SHA256 signature

```ruby
require "moxml"
require "moxml/signature"
require "openssl"

ctx = Moxml.new(:nokogiri)
key = OpenSSL::PKey::RSA.generate(2048)

doc = ctx.parse("<doc><greeting>Hello, World!</greeting></doc>")

# Sign — produces a Model::Signature
signature = Moxml::Signature.sign(
  context: ctx,
  document: doc,
  key: key,
  signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
  canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
  digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
  reference_uri: "",
  transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
)

# Serialize the signature into XML and attach to the document
serialized = Moxml::Signature::Serializer.new(context: ctx).serialize(signature)
doc.root.add_child(serialized.root)

puts doc.to_xml
```

## Verify with the public key

```ruby
result = Moxml::Signature.verify(
  context: ctx,
  document: doc,
  key: key,   # private key works; public key alone is enough
)

puts "Valid: #{result.valid?}"
puts "Signature count: #{result.signature_count}"
result.results.each do |r|
  puts "  signature_valid=#{r.signature_valid?}"
  r.references.each { |ref| puts "    ref #{ref.uri.inspect}: #{ref.valid?}" }
end
```

## Auto-extract key from X509Certificate

```ruby
# sign3-result.xml embeds the signing certificate in KeyInfo.
# No explicit key is needed — the Verifier extracts it automatically.
doc = ctx.parse(File.read("spec/fixtures/xmldsig/sign3-result.xml"))
result = Moxml::Signature.verify(context: ctx, document: doc)
puts "Auto-extracted: #{result.valid?}"
```

## KeyName-based key resolution

```ruby
# Signer used <KeyName>my-key</KeyName>; verifier resolves via key_map:
result = Moxml::Signature.verify(
  context: ctx,
  document: doc,
  key_map: { "my-key" => trusted_public_key },
)
```

## HMAC with truncation

```ruby
signature = Moxml::Signature.sign(
  context: ctx,
  document: doc,
  key: "shared-secret",
  signature_method: "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
  canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
  digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
  reference_uri: "",
  transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
)
```

HMAC `OutputLength` truncation below `max(hash_bits/2, 80)` is rejected.

## Adding a custom algorithm

```ruby
class MyDigest < Moxml::Signature::Algorithms::DigestBase
  identifier "http://example.com/my-digest"

  def compute_digest(data)
    OpenSSL::Digest.digest("SHA3-256", data)
  end
end

# Now usable in any Reference#digest_method
```
