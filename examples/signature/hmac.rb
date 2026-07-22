# frozen_string_literal: true

# Example: HMAC-SHA256 signature with a shared secret.
#
# Run with: bundle exec ruby examples/signature/hmac.rb

require "moxml"
require "moxml/signature"

ctx = Moxml.new(:nokogiri)
secret = "super-secret-shared-key"

doc = ctx.parse("<message><body>hello</body></message>")

signature = Moxml::Signature.sign(
  context: ctx,
  document: doc,
  key: secret,
  signature_method: "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
  canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
  digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
  reference_uri: "",
  transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
)

serialized = Moxml::Signature::Serializer.new(context: ctx).serialize(signature)
doc.root.add_child(serialized.root)

result = Moxml::Signature.verify(context: ctx, document: doc, key: secret)
puts "Valid: #{result.valid?}"

wrong = Moxml::Signature.verify(context: ctx, document: doc, key: "wrong")
puts "Wrong secret: #{wrong.valid?} (expected false)"
