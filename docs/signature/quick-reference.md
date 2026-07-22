# Quick reference

## Public API

```ruby
# Sign a document
signature = Moxml::Signature.sign(
  context:,                   # Moxml::Context (from Moxml.new(:nokogiri))
  document:,                  # Moxml::Document to sign
  key:,                       # OpenSSL::PKey::* or HMAC secret String
  signature_method:,          # algorithm URI
  canonicalization_method:,   # algorithm URI
  digest_method:,             # algorithm URI
  reference_uri:,             # "" for whole document
  transforms:,                # array of algorithm URIs
  key_info: nil,              # optional Model::KeyInfo
  signature_id: nil,          # optional Id attribute
)

# Verify a document
result = Moxml::Signature.verify(
  context:,
  document:,
  key: nil,        # optional; auto-extracted from KeyInfo if absent
  key_map: {},     # for KeyName-based resolution
)
```

## Algorithm URIs

### Digests
- `http://www.w3.org/2000/09/xmldsig#sha1` (verification only)
- `http://www.w3.org/2001/04/xmlenc#sha256` (REQUIRED)
- `http://www.w3.org/2001/04/xmlenc#sha512`
- `http://www.w3.org/2001/04/xmldsig-more#sha224`
- `http://www.w3.org/2001/04/xmldsig-more#sha384`

### Signature methods
- RSA-PKCS1v1.5: `http://www.w3.org/2001/04/xmldsig-more#rsa-sha{1,224,256,384,512}`
- HMAC: `http://www.w3.org/2001/04/xmldsig-more#hmac-sha{1,224,256,384,512}`
- ECDSA: `http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha{1,224,256,384,512}`
- DSA: `http://www.w3.org/2000/09/xmldsig#dsa-sha1`, `http://www.w3.org/2009/xmldsig11#dsa-sha256`

### Canonicalization
- Exclusive: `http://www.w3.org/2001/10/xml-exc-c14n#` (add `#WithComments`)
- Inclusive 1.0: `http://www.w3.org/TR/2001/REC-xml-c14n-20010315`
- Inclusive 1.1: `http://www.w3.org/2006/12/xml-c14n11`

### Transforms
- `http://www.w3.org/2000/09/xmldsig#enveloped-signature`
- `http://www.w3.org/2000/09/xmldsig#base64`

## Common algorithm combinations

### Enveloped RSA-SHA256 (most common)
```ruby
signature_method: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
```

### HMAC-SHA256
```ruby
signature_method: "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
```

### ECDSA-SHA256 (P-256)
```ruby
signature_method: "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256",
canonicalization_method: "http://www.w3.org/2001/10/xml-exc-c14n#",
digest_method: "http://www.w3.org/2001/04/xmlenc#sha256",
transforms: ["http://www.w3.org/2000/09/xmldsig#enveloped-signature"],
```

## Result inspection

```ruby
result.valid?                       # → bool (all signatures)
result.signature_count              # → Integer
result.failing                      # → [SingleVerificationResult]

result.results.first.signature_valid?   # → bool (crypto verify)
result.results.first.references         # → [ReferenceResult]
result.results.first.failing_references # → [ReferenceResult]
result.results.first.error             # → Exception or nil (debugging)
```

## C14N top-level API

```ruby
Moxml::C14n.canonicalize(node_or_xml, with_comments: false)
Moxml::C14n.canonicalize_exclusive(node_or_xml, with_comments: false,
                                   inclusive_namespaces: [])
```

## Errors

```ruby
Moxml::Signature::Error                       # base
Moxml::Signature::SignatureError              # generic
Moxml::Signature::UnknownAlgorithm            # URI not in registry
Moxml::Signature::DuplicateAlgorithm          # URI registered twice
Moxml::Signature::SigningError                # signing failed
Moxml::Signature::VerificationError           # verification failed
Moxml::Signature::ReferenceDigestMismatch     # digest mismatch
Moxml::Signature::SignatureValueMismatch      # crypto verify failed
Moxml::Signature::TransformError              # transform pipeline
Moxml::Signature::CanonicalizationError       # C14N failure
Moxml::Signature::MalformedSignatureError     # XML schema violation
Moxml::Signature::SignatureKeyError           # wrong key type
```
