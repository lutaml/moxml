# frozen_string_literal: true

# Example: enveloped RSA-SHA256 signature with verification.
#
# Run with: bundle exec ruby examples/signature/enveloped_rsa.rb

require "moxml"
require "moxml/signature"
require "openssl"

ctx = Moxml.new(:nokogiri)
key = OpenSSL::PKey::RSA.generate(2048)

doc = ctx.parse("<doc><greeting>Hello, World!</greeting></doc>")
puts "=== Before signing ==="
puts doc.to_xml

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

serialized = Moxml::Signature::Serializer.new(context: ctx).serialize(signature)
doc.root.add_child(serialized.root)

puts ""
puts "=== After signing ==="
puts doc.to_xml

result = Moxml::Signature.verify(context: ctx, document: doc, key: key)
puts ""
puts "=== Verification ==="
puts "Valid: #{result.valid?}"

# Tamper test
doc2 = ctx.parse(doc.to_xml(indent: 0))
doc2.at_xpath("//greeting").text = "Goodbye!"
tampered = Moxml::Signature.verify(context: ctx, document: doc2, key: key)
puts "Tampered: #{tampered.valid?} (expected false)"
