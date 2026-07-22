# frozen_string_literal: true

# Example: auto-extract the verification key from a KeyInfo that
# contains an embedded X509Certificate. The Verifier derives the
# OpenSSL key without application help.
#
# Run with: bundle exec ruby examples/signature/auto_key_extraction.rb

require "moxml"
require "moxml/signature"

ctx = Moxml.new(:nokogiri)

fixture = File.expand_path(
  "../../spec/fixtures/xmldsig/sign3-result.xml",
  __dir__,
)
xml = File.read(fixture)
doc = ctx.parse(xml)

# No explicit key — Verifier auto-extracts from X509Certificate.
result = Moxml::Signature.verify(context: ctx, document: doc)
puts "Auto-extracted from X509Certificate: #{result.valid?}"
puts "Signature count: #{result.signature_count}"
