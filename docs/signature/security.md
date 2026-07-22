# Security considerations

XML signature is a complex spec with a long history of attacks. This
document explains what `Moxml::Signature` does to mitigate them and
what the application is responsible for.

## Built-in mitigations

### Best Practice 1 — authenticate before transforms (DONE)

The Verifier validates `SignatureValue` before running any reference
transforms. A hostile signature with expensive XSLT or XPath transforms
cannot consume server resources unless its `SignatureValue` verifies
against a key the application trusts.

### Best Practice 26 — HMAC truncation floor (DONE)

`HMACOutputLength` values below `max(hash_bits/2, 80)` are rejected
during algorithm instantiation (spec §4.4.2). Signatures with
sub-minimum truncation are deemed invalid.

### Best Practice 11 — opaque certificate handling (DONE)

`X509Certificate` payloads are decoded as raw DER and passed to
`OpenSSL::X509::Certificate.new`. We never re-encode certificates, so
the signature on the certificate itself is preserved.

## What the application must do

The library cannot make trust decisions; the application must.

### Best Practice 2 — establish trust in the key

Just because `SignatureValue` verifies against a public key in
`KeyInfo` does NOT mean the signature should be trusted. The key must
come from a trusted source:

```ruby
# Application-side: pin the expected key, ignore KeyInfo entirely
result = Moxml::Signature.verify(
  context: ctx,
  document: doc,
  key: trusted_public_key,   # do NOT rely on KeyInfo extraction
)

# Or, with certificate validation:
cert = OpenSSL::X509::Certificate.new(cert_der)
store = OpenSSL::X509::Store.new
store.add_trust_file("cacert.pem")
unless store.verify(cert)
  raise "certificate chain invalid"
end

result = Moxml::Signature.verify(
  context: ctx,
  document: doc,
  key: cert.public_key,
)
```

### Best Practice 12 — see what was signed

Use `SingleVerificationResult#references` to inspect what the signature
actually covers:

```ruby
result.results.first.references.each do |ref|
  puts "#{ref.uri}: #{ref.valid?}"
  # Confirm ref.uri matches what the application expects to be signed.
  # Wrapping attacks work by getting the verifier to confirm a different
  # node than the application acts on.
end
```

### Best Practice 14 — check name AND position

When checking a reference URI, don't just verify the element name. A
wrapping attack moves the signed element into an `<Object>` and points
the reference at it; the application then acts on a different (unsigned)
element with the same name.

### Best Practice 8 — control external references

External URI dereferencing is **not enabled by default**. If you need
it, wrap the resolver in a policy that:

- Allows only same-document URIs (`#id`, `""`)
- Allows only specific schemes (`https://`, never `file://`)
- Caps size and timeout
- Disallows query parameters that mutate server state

## What this library does NOT do

### Not a chain validator

`Moxml::Signature` does not validate X.509 certificate chains, check
revocation, or evaluate certificate policies. The application is
responsible for these (see Best Practice 2 above).

### Not a timestamp authority

Long-lived signatures need RFC 3161 timestamps from a TSA. This library
does not implement timestamp verification.

### Not a wrapping-attack detector

Wrapping attacks succeed when the application acts on a different node
than the one the signature actually covers. The library returns the
list of references; the application must verify they cover the right
nodes.

## SHA-1 warning

The W3C spec marks SHA-1 as REQUIRED for backwards compatibility but
DISCOURAGED for new signatures. Cryptanalytic advances (SHAttered,
2017) demonstrated practical collisions. Use SHA-256 or stronger for
new signatures.

## HMAC security

HMAC signatures require a shared secret. Any verifier with the secret
can forge signatures. Use distinct keys for signing vs. encryption
(Best Practice 27).

## Limited XPath support

The library implements the Enveloped Signature transform directly
(no XPath). XPath Filter and XSLT transforms are not implemented;
Best Practices 3, 5, 6, 22 say avoid them.

## Performance and DoS

Canonicalization is O(N) for tree size. XSLT and complex XPath are
not supported, eliminating the most common DoS vectors (Best Practices
3, 5, 6). Wrap calls in a timeout if processing untrusted input:

```ruby
require "timeout"

Timeout.timeout(5) do
  Moxml::Signature.verify(context: ctx, document: untrusted_doc, key:)
end
```
