# Signing and verification flows

## Signer (spec §3.1)

```
Moxml::Signature.sign(context:, document:, key:, **options)
        │
        ▼
build a Model::Signature with the requested algorithms
        │
        ▼
Signer#sign
        │
        ├── for each Reference in SignedInfo:
        │     ├── ReferenceResolver.resolve(uri)        → node or octets
        │     ├── TransformPipeline.apply(input, transforms)
        │     ├── TransformPipeline.to_octets(transformed, reference)
        │     └── DigestMethod#digest_base64(canonical) → Reference#digest_value
        │
        ├── Serializer.serialize_signed_info(signed_info)  → Moxml::Document
        ├── CanonicalizationMethod#canonicalize(signed_info_root) → octets
        └── SignatureMethod#sign(canonical_octets, key)   → SignatureValue
```

The Signer never touches algorithms directly — every step delegates to
the algorithm registry. This is OCP: new algorithms are added without
touching the Signer.

## Verifier (spec §3.2 + Best Practice 1)

```
Moxml::Signature.verify(context:, document:, key: nil, key_map: {})
        │
        ▼
find all ds:Signature elements in the document
        │
        ▼ for each Signature
verify_one(signature_element)
        │
        ├── Parser.parse(signature_element)   → Model::Signature
        │
        ├── verify_signature_value FIRST   (Best Practice 1)
        │     ├── find original SignedInfo element (do NOT re-serialize)
        │     ├── CanonicalizationMethod#canonicalize(signed_info_elem)
        │     ├── resolve_key(signature)   (KeyExtractor if no key:)
        │     └── SignatureMethod#verify(canonical, key, sig_value)
        │
        └── if signature value verifies:
              for each Reference:
                ├── ReferenceResolver.resolve(uri)
                ├── TransformPipeline.apply(...)
                ├── TransformPipeline.to_octets(...)
                └── DigestMethod#digest_base64 vs Reference#digest_value
```

### Best Practice 1: authenticate before transforms

The verifier deliberately runs `SignatureValue` validation BEFORE
applying any transforms. Reason: a malicious signature could include
XSLT or expensive XPath transforms. Best Practice 1 says only run
those after authenticating the signer.

If `SignatureValue` doesn't verify, we skip reference transforms
entirely. The result object reports `signature_valid?: false` and
`references: []`.

### Why we canonicalize the original element

The verifier canonicalizes the SignedInfo **as it appears in the
document**, not a re-serialized model. Reason: re-serialization could
change namespace prefixes (e.g., default-namespace SignedInfo might
become `ds:SignedInfo`), breaking the byte-exact match the signature
was computed against.

The Signer serializes (it has to — it's building new XML). The Verifier
has the original element from the document and uses it directly. This
asymmetry is intentional and necessary for cross-verification with
libxmlsec1-produced signatures.

### Errors are captured, not raised

`SingleVerificationResult#error` carries any `VerificationError` or
`UnknownAlgorithm` that caused failure. The verifier returns a result
object rather than raising, so a hostile signature cannot panic the
application. Use `result.results.first.error` for debugging.

## Key resolution

```ruby
Moxml::Signature.verify(context:, document:)  # no key:
```

When no `key:` is passed, the Verifier uses `KeyExtractor` to derive
one from the signature's `KeyInfo`:

1. **X509Certificate** (preferred) — decode base64 DER →
   `OpenSSL::X509::Certificate` → `.public_key`
2. **RSAKeyValue** — reconstruct via ASN.1 (OpenSSL 3.x dropped
   `RSA.new(n, e)`)
3. **DSAKeyValue** — reconstruct via ASN.1
4. **ECKeyValue** — build SubjectPublicKeyInfo DER for the named curve
   (OpenSSL 3.x made PKey immutable)
6. **KeyName** — look up in the application-supplied `key_map:`

OpenSSL 3.x compatibility notes are inline in `key_extractor.rb`.

## Transform pipeline

`TransformPipeline` is shared by Signer and Verifier. Each Transform
in the chain declares `input_type` (`:octets` or `:nodeset`) and
`output_type`; the pipeline coerces types between transforms per
spec §4.4.3.2:

- `octets → nodeset`: parse as XML via the caller's `context:`
- `nodeset → octets`: apply inclusive C14N 1.0

Final conversion to octets (for digesting) uses the last canonicalization
transform in the chain if any, else inclusive C14N 1.0 as the spec default.

## Result objects

```ruby
result = Moxml::Signature.verify(context:, document:, key:)
result.valid?              # → bool (all signatures valid)
result.signature_count     # → Integer
result.results             # → [SingleVerificationResult, ...]
result.results.first.signature_valid?
result.results.first.references       # → [ReferenceResult, ...]
result.results.first.references.first.valid?
result.results.first.error            # → Exception or nil
result.failing            # → [SingleVerificationResult, ...]
```
